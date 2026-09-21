#!/bin/bash
# xgem ci diagnosis: turns a failed step's log into grouped root causes with
# the exact location, why it happens, and how to fix it.
# Findings are TSV: sev file line col code msg name detail (detail lines are
# joined with \036). bash 3.2 / BSD awk safe: no asort, no intervals.
# Depends on lib/logger.sh.

DIAG_AUTOFIX=()

_diag_kb() {
    echo "${XGEM_HOME:?}/templates/ci/fixes.tsv"
}

_diag_clean() {
    sed -E $'s/\033\\[[0-9;?]*[A-Za-z]//g' "$1" | tr -d '\r'
}

_DIAG_AWK_LIB='
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }
function emit(sev, file, line, col, code, msg, name, detail) {
    gsub(/\t/, " ", msg); gsub(/\t/, " ", name); gsub(/\t/, " ", detail)
    if (trim(msg) == "") msg = "(no message)"
    if (file == "") file = "-"
    if (line == "") line = "-"
    if (col == "") col = "-"
    if (code == "") code = "-"
    if (name == "") name = "-"
    if (detail == "") detail = "-"
    print sev, file, line, col, code, trim(msg), name, detail
}
function splitloc(s, out,    n, a, i, f) {
    n = split(s, a, ":")
    f = a[1]
    for (i = 2; i <= n - 2; i++) f = f ":" a[i]
    out["file"] = f; out["line"] = a[n - 1]; out["col"] = a[n]
}
'

_diag_parse_dart_analyze() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    /^ *(error|warning|info|hint) • / {
        n = split($0, p, " • ")
        if (n < 4) next
        sev = trim(p[1]); if (sev == "hint") sev = "info"
        rule = trim(p[n]); loc = trim(p[n - 1])
        msg = p[2]; for (i = 3; i <= n - 2; i++) msg = msg " • " p[i]
        splitloc(loc, L)
        emit(sev, L["file"], L["line"], L["col"], rule, msg, "", "")
    }' "$1"
}

_diag_parse_flutter_test() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    function flush(   msg, det) {
        if (!active) return
        if (ex != "") { msg = name ": " ex " " ac; det = ex; if (ac != "") det = det "\036" ac; if (wh != "") det = det "\036" wh }
        else { msg = name ": " first; det = "" }
        emit("fail", file, line, col, "", msg, name, det)
        active = 0; ex = ""; ac = ""; wh = ""; file = ""; line = ""; col = ""; first = ""
    }
    /^[0-9:]+ \+[0-9]+( -[0-9]+)?: .* \[E\]$/ {
        flush()
        name = $0; sub(/^[0-9:]+ \+[0-9]+( -[0-9]+)?: /, "", name); sub(/ \[E\]$/, "", name)
        active = 1; next
    }
    /^[0-9:]+ \+[0-9]+( -[0-9]+)?: / { flush(); next }
    active && /^ +Expected:/ { ex = trim($0); next }
    active && /^ +Actual:/ { ac = trim($0); next }
    active && /^ +Which:/ { wh = trim($0); next }
    active && file == "" && /^ +[A-Za-z0-9_.\/-]+\.dart [0-9]+:[0-9]+ / {
        if ($1 !~ /^package:/ && $1 !~ /^dart:/) { file = $1; split($2, lc, ":"); line = lc[1]; col = lc[2] }
        next
    }
    active && first == "" && NF > 0 && $0 !~ /^ *(package:|dart:)/ && $0 !~ /^ +[A-Za-z0-9_.\/-]+\.dart / { first = trim($0) }
    END { flush() }' "$1"
}

_diag_parse_ts() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    function flush_esb() {
        if (pend) emit("error", pfile, pline, pcol, pcode, pmsg, "", "")
        pend = 0; pfile = ""; pline = ""; pcol = ""
    }
    match($0, /\([0-9]+,[0-9]+\): (error|warning) TS[0-9]+: /) {
        head = substr($0, RSTART, RLENGTH); file = substr($0, 1, RSTART - 1); msg = substr($0, RSTART + RLENGTH)
        match(head, /[0-9]+,[0-9]+/); split(substr(head, RSTART, RLENGTH), a, ",")
        ln = a[1]; cl = a[2]
        match(head, /TS[0-9]+/); code = substr(head, RSTART, RLENGTH)
        emit((head ~ /error/) ? "error" : "warning", file, ln, cl, code, msg, "", "")
        next
    }
    match($0, / - (error|warning) TS[0-9]+: /) {
        head = substr($0, RSTART, RLENGTH); locs = substr($0, 1, RSTART - 1); msg = substr($0, RSTART + RLENGTH)
        match(head, /TS[0-9]+/); code = substr(head, RSTART, RLENGTH)
        splitloc(locs, L)
        emit((head ~ /error/) ? "error" : "warning", L["file"], L["line"], L["col"], code, msg, "", "")
        next
    }
    /^[^ ].*\[ERROR\] / {
        flush_esb()
        m = $0; sub(/^.*\[ERROR\] /, "", m); sub(/ \[plugin [^]]*\]$/, "", m)
        pcode = ""
        if (match(m, /^[A-Z]+[0-9]+: /)) { pcode = substr(m, RSTART, RLENGTH - 2); m = substr(m, RLENGTH + 1) }
        pmsg = m; pend = 1; next
    }
    pend && /^ +[^ :]+:[0-9]+:[0-9]+:$/ {
        s = trim($0); sub(/:$/, "", s); splitloc(s, L); pfile = L["file"]; pline = L["line"]; pcol = L["col"]
        flush_esb(); next
    }
    END { flush_esb() }' "$1"
}

_diag_parse_eslint() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    /^ +[0-9]+:[0-9]+ +(error|warning) / {
        s = $0; sub(/^ +/, "", s)
        split(s, w, " +"); split(w[1], lc, ":"); sev = w[2]
        sub(/^[0-9]+:[0-9]+ +(error|warning) +/, "", s)
        rule = ""
        if (match(s, /  +[^ ]+$/)) {
            r = substr(s, RSTART); gsub(/^ +/, "", r)
            if (r ~ /^[@A-Za-z0-9_\/.-]+$/) { rule = r; s = substr(s, 1, RSTART - 1) }
        }
        emit(sev, file, lc[1], lc[2], rule, s, "", "")
        next
    }
    /^[^ ]/ && $0 !~ /^(✖|>|npm )/ && $0 !~ /[0-9]+:[0-9]+ +(error|warning) / { file = trim($0) }' "$1"
}

_diag_parse_vitest() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    function flush(   i) {
        for (i = 1; i <= nn; i++) emit("fail", vfile, vline, vcol, "", vmsg, names[i], vdetail)
        nn = 0; vmsg = ""; vdetail = ""; vfile = ""; vline = ""; vcol = ""; state = 0; dl = 0
    }
    /^ FAIL  / {
        if (state == 2) flush()
        nm = $0; sub(/^ FAIL  /, "", nm); sub(/ \[ .* \]$/, "", nm)
        names[++nn] = nm; state = 1; next
    }
    state == 1 && NF > 0 { vmsg = trim($0); state = 2; next }
    state == 2 && /^ ❯ / {
        if (match($0, /[^ ]+:[0-9]+:[0-9]+$/)) {
            loc = substr($0, RSTART)
            if (vfile == "" && loc !~ /node_modules/) { splitloc(loc, L); vfile = L["file"]; vline = L["line"]; vcol = L["col"] }
        }
        next
    }
    state == 2 && /^⎯/ { flush(); next }
    state == 2 && vfile == "" && NF > 0 && dl < 8 && $0 !~ /^ +[0-9]+\|/ {
        vdetail = vdetail (vdetail == "" ? "" : "\036") trim($0); dl++
    }
    /Startup Error|Unhandled (Errors|Rejection)/ { su = 1; next }
    su && NF > 0 && $0 !~ /^Vitest caught/ && $0 !~ /^⎯/ { emit("error", "", "", "", "", trim($0), "", ""); su = 0 }
    END { flush() }' "$1"
}

_diag_parse_jest() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    function flush() {
        if (!active) return
        dm = jdet; gsub(/\036/, " ", dm)
        emit("fail", jfile, jline, jcol, "", jmsg (dm == "" ? "" : ": " dm), jname, jdet)
        active = 0; jmsg = ""; jdet = ""; jfile = ""; jline = ""; jcol = ""
    }
    /^  ● / && $0 !~ /● Console/ { flush(); jname = $0; sub(/^  ● /, "", jname); active = 1; next }
    active && jmsg == "" && NF > 0 { jmsg = trim($0); next }
    active && /^ +(Expected|Received)/ { t = trim($0); jdet = jdet (jdet == "" ? "" : "\036") t; next }
    active && jfile == "" && /^ +at / && $0 !~ /node_modules/ {
        if (match($0, /\(?[^ (]+:[0-9]+:[0-9]+\)?$/)) {
            loc = substr($0, RSTART, RLENGTH); gsub(/[()]/, "", loc); splitloc(loc, L)
            jfile = L["file"]; jline = L["line"]; jcol = L["col"]
        }
        next
    }
    END { flush() }' "$1"
}

_diag_parse_cargo() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    function flush() {
        if (active && msg !~ /^(could not compile|aborting due to|.*generated [0-9]+ warning|.*due to [0-9]+ previous error|Some errors have detailed|test failed)/ && msg !~ /^For more information/)
            emit(sev, file, line, col, code, msg, "", "")
        active = 0; file = ""; line = ""; col = ""; code = ""
    }
    /^(error|warning)(\[E[0-9]+\])?: / {
        flush()
        s = $0; sev = (substr(s, 1, 5) == "error") ? "error" : "warning"
        code = ""
        if (match(s, /\[E[0-9]+\]/)) code = substr(s, RSTART + 1, RLENGTH - 2)
        sub(/^(error|warning)(\[E[0-9]+\])?: /, "", s); msg = s; active = 1; next
    }
    active && /^ *--> / {
        s = $0; sub(/^ *--> /, "", s); splitloc(s, L); file = L["file"]; line = L["line"]; col = L["col"]; next
    }
    active && /#\[warn\(/ && code == "" {
        if (match($0, /warn\([a-z_]+\)/)) code = "rust:" substr($0, RSTART + 5, RLENGTH - 6)
    }
    END { flush() }' "$1"
}

_diag_parse_go() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    /^[^ :]+\.go:[0-9]+:[0-9]+: / {
        s = $0; match(s, /^[^ :]+\.go:[0-9]+:[0-9]+: /)
        head = substr(s, 1, RLENGTH - 2); msg = substr(s, RLENGTH + 1)
        splitloc(head, L)
        emit("error", L["file"], L["line"], L["col"], "", msg, "", "")
    }' "$1"
}

_diag_parse_generic() {
    awk -v OFS='\t' "$_DIAG_AWK_LIB"'
    /(error|Error|ERROR|failed|FAILED)/ && match($0, /[A-Za-z0-9_.\/-]+\.[A-Za-z]+:[0-9]+(:[0-9]+)?/) {
        loc = substr($0, RSTART, RLENGTH); rest = $0
        if (loc !~ /^[0-9]/ && loc !~ /https?:/) {
            n = split(loc, a, ":"); ln = a[2]; cl = (n >= 3) ? a[3] : ""
            emit("error", a[1], ln, cl, "", trim(rest), "", "")
        }
    }' "$1"
}

_diag_findings() {
    local clean=$1 out
    out=$({
        _diag_parse_dart_analyze "$clean"
        _diag_parse_flutter_test "$clean"
        _diag_parse_ts "$clean"
        _diag_parse_eslint "$clean"
        _diag_parse_vitest "$clean"
        _diag_parse_jest "$clean"
        _diag_parse_cargo "$clean"
        _diag_parse_go "$clean"
    })
    [ -z "$out" ] && out=$(_diag_parse_generic "$clean")
    [ -n "$out" ] && printf '%s\n' "$out"
}

# Sorted cluster records: rank negcount key seq TYPE fields...
_diag_cluster() {
    awk -F'\t' -v OFS='\t' -v kb="$(_diag_kb)" '
    function rank(s) { return (s == "error" || s == "fail") ? 0 : (s == "warning" ? 1 : 2) }
    function norm(m) {
        gsub(/\$\{[^}]*\}/, "", m); gsub(/[0-9]+/, "N", m); gsub(/[ ]+/, " ", m)
        return substr(m, 1, 100)
    }
    BEGIN {
        while ((getline ln < kb) > 0) {
            if (ln ~ /^#/ || ln == "") continue
            split(ln, f, "\t"); k++
            id[k] = f[1]; kind[k] = f[2]; pat[k] = f[3]; grp[k] = f[8]
        }
        close(kb)
    }
    {
        sev = $1; file = $2; code = $5; msg = $6
        key = ""; kid = "-"
        if (code != "-") for (i = 1; i <= k; i++) if (kind[i] == "code" && pat[i] == code) { kid = id[i]; key = code; break }
        if (kid == "-") for (i = 1; i <= k; i++) if (kind[i] == "regex" && match(msg, pat[i])) {
            kid = id[i]; key = (grp[i] == "match") ? substr(msg, RSTART, RLENGTH) : id[i]; break
        }
        if (key == "") key = (code != "-") ? code : norm(msg)
        if (!(key in cnt)) { order[++nk] = key; cnt[key] = 0; ksev[key] = 9; kkid[key] = kid; kcode[key] = code }
        cnt[key]++
        if (rank(sev) < ksev[key]) ksev[key] = rank(sev)
        fk = key SUBSEP file
        if (file != "-" && !(fk in seen)) { seen[fk] = 1; nf[key]++ }
        ek = key SUBSEP file SUBSEP $3 SUBSEP msg
        if (!(ek in exid) && ex[key] < 3) { ex[key]++; exid[ek] = ex[key]; e[key, ex[key]] = $2 "\t" $3 "\t" $4 "\t" msg "\t" $8 }
        if (ek in exid) {
            j = exid[ek]; en[key, j]++
            if (en[key, j] <= 3 && $7 != "-") nm[key, j] = nm[key, j] (nm[key, j] == "" ? "" : " | ") $7
        }
    }
    END {
        for (i = 1; i <= nk; i++) {
            key = order[i]
            print ksev[key], -cnt[key], key, 0, "C", cnt[key], nf[key] + 0, kkid[key], kcode[key]
            for (j = 1; j <= ex[key]; j++) {
                split(e[key, j], q, "\t")
                names = nm[key, j]
                if (en[key, j] > 3 && names != "") names = names " (+" (en[key, j] - 3) " more)"
                if (names == "") names = "-"
                print ksev[key], -cnt[key], key, j, "X", q[1], q[2], q[3], q[4], names, q[5]
            }
        }
    }' | sort -t $'\t' -k1,1n -k2,2n -k3,3 -k4,4n
}

_diag_snippet() {
    local file=$1 line=$2 col=$3 text pad caret_pad
    [ "$file" = "-" ] || [ "$line" = "-" ] && return 0
    case "$file" in *node_modules*) return 0 ;; esac
    [ -f "$file" ] || return 0
    text=$(sed -n "${line}p" "$file" | tr '\t' ' ' | cut -c1-140)
    [ -n "$text" ] || return 0
    pad=$(printf '%*s' "${#line}" "")
    printf '        %s | %s\n' "$line" "$text"
    if [ "$col" != "-" ] && [ "$col" -gt 0 ] 2>/dev/null; then
        caret_pad=$(printf '%*s' "$((col - 1))" "")
        printf '        %s | %s^\n' "$pad" "$caret_pad"
    fi
}

_diag_kb_row() {
    awk -F'\t' -v id="$1" '$1 == id { print; exit }' "$(_diag_kb)"
}

_diag_node_pm() {
    if [ -f pnpm-lock.yaml ]; then echo pnpm
    elif [ -f yarn.lock ]; then echo yarn
    elif [ -f bun.lockb ] || [ -f bun.lock ]; then echo bun
    else echo npm; fi
}

# _diag_resolve_autofix <template> -> a runnable command, or empty when it doesn't apply here.
_diag_resolve_autofix() {
    case "$1" in
        "@LINT_FIX@")
            [ -f package.json ] || return 0
            grep -E '"lint"[[:space:]]*:[[:space:]]*"[^"]*(eslint|ng lint)' package.json >/dev/null 2>&1 || return 0
            case "$(_diag_node_pm)" in
                yarn) echo "yarn lint --fix" ;;
                pnpm) echo "pnpm run lint --fix" ;;
                bun)  echo "bun run lint --fix" ;;
                *)    echo "npm run lint -- --fix" ;;
            esac
            ;;
        "dart fix --apply") [ -f pubspec.yaml ] && echo "$1" ;;
        cargo*)             [ -f Cargo.toml ] && [ "${_dp_has_errors:-0}" = "0" ] && echo "$1" ;;
        *)                  echo "$1" ;;
    esac
}

_diag_register_autofix() {
    local cmd=$1 existing
    [ -n "$cmd" ] || return 0
    for existing in ${DIAG_AUTOFIX[@]+"${DIAG_AUTOFIX[@]}"}; do
        [ "$existing" = "$cmd" ] && return 0
    done
    DIAG_AUTOFIX+=("$cmd")
}

_diag_short() {
    printf '%s' "$1" | cut -c1-"${2:-160}"
}

_diag_footer() {
    [ -n "$_dp_why" ] && echo "      Why:  $_dp_why"
    [ -n "$_dp_fix" ] && echo "      Fix:  $_dp_fix"
    [ -n "$_dp_auto" ] && echo "      Auto: $_dp_auto   (xgem ci --fix runs this)"
    [ -n "$_dp_docs" ] && [ "$_dp_docs" != "-" ] && echo "      Docs: $_dp_docs"
    if [ -z "$_dp_why" ] && [ -z "$_dp_fix" ]; then
        echo "      (no known fix for this one; the location and message above are the real problem)"
    fi
    return 0
}

# diag_cluster_summary <log>: key<TAB>count<TAB>files<TAB>kbid per cluster.
diag_cluster_summary() {
    local clean
    clean=$(mktemp)
    _diag_clean "$1" > "$clean"
    _diag_findings "$clean" | _diag_cluster | awk -F'\t' '$5 == "C" { print $3 "\t" $6 "\t" $7 "\t" $8 }'
    rm -f "$clean"
}

# diagnose_step <label> <log>: prints grouped root causes; registers auto-fixes.
diagnose_step() {
    local label=$1 log=$2 clean findings records total distinct
    clean=$(mktemp)
    _diag_clean "$log" > "$clean"
    findings=$(_diag_findings "$clean")

    if [ -z "$findings" ]; then
        echo ""
        echo -e "${_c_red}FAIL${_c_reset} $label   (no file/line could be extracted; last lines of the log)"
        grep -v '^[[:space:]]*$' "$clean" | tail -15 | sed 's/^/    /'
        echo "    full log: $log"
        rm -f "$clean"
        return 0
    fi

    _dp_has_errors=0
    printf '%s\n' "$findings" | awk -F'\t' '$1 == "error" { f = 1 } END { exit !f }' && _dp_has_errors=1
    total=$(printf '%s\n' "$findings" | wc -l | tr -d ' ')
    records=$(printf '%s\n' "$findings" | _diag_cluster)
    distinct=$(printf '%s\n' "$records" | awk -F'\t' '$5 == "C"' | wc -l | tr -d ' ')

    echo ""
    echo -e "${_c_red}FAIL${_c_reset} $label   ($total finding$([ "$total" = 1 ] || echo s), $distinct distinct cause$([ "$distinct" = 1 ] || echo s))   full log: $log"

    local shown=0 more=0 printing=0 key type f1 f2 f3 f4 f5 f6 row autofix title
    _dp_why=""; _dp_fix=""; _dp_docs=""; _dp_auto=""
    local _dp_root
    _dp_root=$(pwd -P)
    while IFS=$'\t' read -r _r _n key _s type f1 f2 f3 f4 f5 f6; do
        if [ "$type" = "C" ]; then
            [ "$printing" = "1" ] && _diag_footer
            printing=0
            if [ "$shown" -ge 5 ]; then more=$((more + 1)); continue; fi
            shown=$((shown + 1)); printing=1
            _dp_why=""; _dp_fix=""; _dp_docs=""; _dp_auto=""
            if [ "$f3" != "-" ]; then
                row=$(_diag_kb_row "$f3")
                _dp_why=$(printf '%s' "$row" | cut -f4)
                _dp_fix=$(printf '%s' "$row" | cut -f5)
                autofix=$(printf '%s' "$row" | cut -f6)
                _dp_docs=$(printf '%s' "$row" | cut -f7)
                [ "$autofix" != "-" ] && _dp_auto=$(_diag_resolve_autofix "$autofix")
                case "$key" in */*) _dp_docs="-" ;; esac
                _dp_docs=${_dp_docs//@CODE@/${key#rust:}}
                _diag_register_autofix "$_dp_auto"
            fi
            title=${key#rust:}
            echo ""
            printf ' %d) %s  x%s' "$shown" "$title" "$f1"
            [ "$f2" -gt 0 ] 2>/dev/null && printf ' in %s file%s' "$f2" "$([ "$f2" = 1 ] || echo s)"
            [ -n "$_dp_auto" ] && printf '   [auto-fixable]'
            echo ""
            continue
        fi
        [ "$printing" = "1" ] || continue
        f1=${f1#"$_dp_root"/}
        if [ "$f1" != "-" ]; then
            printf '    %s%s%s  %s\n' "$f1" "$([ "$f2" != "-" ] && echo ":$f2")" "$([ "$f3" != "-" ] && echo ":$f3")" "$(_diag_short "$f4")"
        else
            printf '    %s\n' "$(_diag_short "$f4")"
        fi
        [ "$f5" != "-" ] && printf '        tests: %s\n' "$(_diag_short "$f5" 200)"
        _diag_snippet "$f1" "$f2" "$f3"
        if [ "$f6" != "-" ]; then
            printf '%s\n' "$f6" | tr '\036' '\n' | head -6 | sed 's/^/        > /'
        fi
    done <<< "$records"
    [ "$printing" = "1" ] && _diag_footer

    [ "$more" -gt 0 ] && { echo ""; echo "    (+$more more distinct cause$([ "$more" = 1 ] || echo s) in the full log)"; }
    rm -f "$clean"
    return 0
}
