// xgem Windows engine ci diagnosis — port of lib/ci-diagnose.sh. Reads the
// same templates/ci/fixes.tsv knowledge base, so both engines explain a
// failure identically. Checked against the same real-output fixtures.

const fs = require('node:fs');
const path = require('node:path');

const KB_FILE = path.join(__dirname, '..', 'templates', 'ci', 'fixes.tsv');
const ANSI = /\x1b\[[0-9;?]*[A-Za-z]/g;
const SEP = '\x1e';

const clean = (text) => text.replace(ANSI, '').replace(/\r/g, '');
const trim = (s) => s.trim();

function finding(sev, file, line, col, code, msg, name, detail) {
    return {
        sev,
        file: file || '-',
        line: line || '-',
        col: col || '-',
        code: code || '-',
        msg: trim(msg) || '(no message)',
        name: name || '-',
        detail: detail || '-',
    };
}

function splitLoc(s) {
    const parts = s.split(':');
    return { file: parts.slice(0, -2).join(':'), line: parts[parts.length - 2], col: parts[parts.length - 1] };
}

function parseDartAnalyze(lines) {
    const out = [];
    for (const l of lines) {
        if (!/^ *(error|warning|info|hint) • /.test(l)) continue;
        const p = l.split(' • ');
        if (p.length < 4) continue;
        const sev = trim(p[0]) === 'hint' ? 'info' : trim(p[0]);
        const loc = splitLoc(trim(p[p.length - 2]));
        out.push(finding(sev, loc.file, loc.line, loc.col, trim(p[p.length - 1]), p.slice(1, -2).join(' • '), '', ''));
    }
    return out;
}

function parseFlutterTest(lines) {
    const out = [];
    let cur = null;
    const flush = () => {
        if (!cur) return;
        let msg;
        let det = '';
        if (cur.ex) {
            msg = `${cur.name}: ${cur.ex} ${cur.ac}`;
            det = [cur.ex, cur.ac, cur.wh].filter(Boolean).join(SEP);
        } else {
            msg = `${cur.name}: ${cur.first}`;
        }
        out.push(finding('fail', cur.file, cur.line, cur.col, '', msg, cur.name, det));
        cur = null;
    };
    for (const l of lines) {
        let m = l.match(/^[0-9:]+ \+[0-9]+( -[0-9]+)?: (.*) \[E\]$/);
        if (m) { flush(); cur = { name: m[2], ex: '', ac: '', wh: '', file: '', line: '', col: '', first: '' }; continue; }
        if (/^[0-9:]+ \+[0-9]+( -[0-9]+)?: /.test(l)) { flush(); continue; }
        if (!cur) continue;
        if (/^ +Expected:/.test(l)) { cur.ex = trim(l); continue; }
        if (/^ +Actual:/.test(l)) { cur.ac = trim(l); continue; }
        if (/^ +Which:/.test(l)) { cur.wh = trim(l); continue; }
        m = l.match(/^ +([A-Za-z0-9_.\/-]+\.dart) ([0-9]+):([0-9]+) /);
        if (m && !cur.file) {
            if (!/^package:|^dart:/.test(m[1])) { cur.file = m[1]; cur.line = m[2]; cur.col = m[3]; }
            continue;
        }
        if (!cur.first && trim(l) && !/^ *(package:|dart:)/.test(l) && !/^ +[A-Za-z0-9_.\/-]+\.dart /.test(l)) cur.first = trim(l);
    }
    flush();
    return out;
}

function parseTs(lines) {
    const out = [];
    let pend = null;
    const flush = () => {
        if (pend) out.push(finding('error', pend.file, pend.line, pend.col, pend.code, pend.msg, '', ''));
        pend = null;
    };
    for (const l of lines) {
        let m = l.match(/^(.*)\((\d+),(\d+)\): (error|warning) (TS\d+): (.*)$/);
        if (m) { out.push(finding(m[4], m[1], m[2], m[3], m[5], m[6], '', '')); continue; }
        m = l.match(/^(.*) - (error|warning) (TS\d+): (.*)$/);
        if (m) { const loc = splitLoc(m[1]); out.push(finding(m[2], loc.file, loc.line, loc.col, m[3], m[4], '', '')); continue; }
        if (/^[^ ].*\[ERROR\] /.test(l)) {
            flush();
            let msg = l.replace(/^.*\[ERROR\] /, '').replace(/ \[plugin [^\]]*\]$/, '');
            let code = '';
            const c = msg.match(/^([A-Z]+[0-9]+): /);
            if (c) { code = c[1]; msg = msg.slice(c[0].length); }
            pend = { msg, code, file: '', line: '', col: '' };
            continue;
        }
        if (pend && /^ +[^ :]+:[0-9]+:[0-9]+:$/.test(l)) {
            const loc = splitLoc(trim(l).replace(/:$/, ''));
            Object.assign(pend, loc);
            flush();
        }
    }
    flush();
    return out;
}

function parseEslint(lines) {
    const out = [];
    let file = '';
    for (const l of lines) {
        let m = l.match(/^ +([0-9]+):([0-9]+) +(error|warning) +(.*)$/);
        if (m) {
            let msg = m[4];
            let rule = '';
            const r = msg.match(/^(.*?) {2,}([^ ]+)$/);
            if (r && /^[@A-Za-z0-9_\/.-]+$/.test(r[2])) { msg = r[1]; rule = r[2]; }
            out.push(finding(m[3], file, m[1], m[2], rule, msg, '', ''));
            continue;
        }
        if (/^[^ ]/.test(l) && !/^(✖|>|npm )/.test(l) && !/[0-9]+:[0-9]+ +(error|warning) /.test(l)) file = trim(l);
    }
    return out;
}

function parseVitest(lines) {
    const out = [];
    let names = [];
    let state = 0;
    let v = { msg: '', detail: [], file: '', line: '', col: '' };
    let su = false;
    const flush = () => {
        for (const n of names) out.push(finding('fail', v.file, v.line, v.col, '', v.msg, n, v.detail.join(SEP)));
        names = [];
        state = 0;
        v = { msg: '', detail: [], file: '', line: '', col: '' };
    };
    for (const l of lines) {
        if (l.startsWith(' FAIL  ')) {
            if (state === 2) flush();
            names.push(l.slice(7).replace(/ \[ .* \]$/, ''));
            state = 1;
            continue;
        }
        if (state === 1 && trim(l)) { v.msg = trim(l); state = 2; continue; }
        if (state === 2 && l.startsWith(' ❯ ')) {
            const m = l.match(/[^ ]+:[0-9]+:[0-9]+$/);
            if (m && !v.file && !/node_modules/.test(m[0])) Object.assign(v, splitLoc(m[0]));
            continue;
        }
        if (state === 2 && l.startsWith('⎯')) { flush(); continue; }
        if (state === 2 && !v.file && trim(l) && v.detail.length < 8 && !/^ +[0-9]+\|/.test(l)) v.detail.push(trim(l));
        if (/Startup Error|Unhandled (Errors|Rejection)/.test(l)) { su = true; continue; }
        if (su && trim(l) && !/^Vitest caught/.test(l) && !l.startsWith('⎯')) { out.push(finding('error', '', '', '', '', trim(l), '', '')); su = false; }
    }
    flush();
    return out;
}

function parseJest(lines) {
    const out = [];
    let cur = null;
    const flush = () => {
        if (!cur) return;
        const dm = cur.det.join(' ');
        out.push(finding('fail', cur.file, cur.line, cur.col, '', cur.msg + (dm ? `: ${dm}` : ''), cur.name, cur.det.join(SEP)));
        cur = null;
    };
    for (const l of lines) {
        if (/^ {2}● /.test(l) && !/● Console/.test(l)) { flush(); cur = { name: l.slice(4), msg: '', det: [], file: '', line: '', col: '' }; continue; }
        if (!cur) continue;
        if (!cur.msg && trim(l)) { cur.msg = trim(l); continue; }
        if (/^ +(Expected|Received)/.test(l)) { cur.det.push(trim(l)); continue; }
        if (!cur.file && /^ +at /.test(l) && !/node_modules/.test(l)) {
            const m = l.match(/\(?[^ (]+:[0-9]+:[0-9]+\)?$/);
            if (m) Object.assign(cur, splitLoc(m[0].replace(/[()]/g, '')));
        }
    }
    flush();
    return out;
}

function parseCargo(lines) {
    const out = [];
    let cur = null;
    const skip = /^(could not compile|aborting due to|.*generated [0-9]+ warning|.*due to [0-9]+ previous error|Some errors have detailed|test failed)|^For more information/;
    const flush = () => {
        if (cur && !skip.test(cur.msg)) out.push(finding(cur.sev, cur.file, cur.line, cur.col, cur.code, cur.msg, '', ''));
        cur = null;
    };
    for (const l of lines) {
        const m = l.match(/^(error|warning)(\[(E[0-9]+)\])?: (.*)$/);
        if (m) { flush(); cur = { sev: m[1], code: m[3] || '', msg: m[4], file: '', line: '', col: '' }; continue; }
        if (!cur) continue;
        const a = l.match(/^ *--> (.*)$/);
        if (a) { Object.assign(cur, splitLoc(a[1])); continue; }
        const w = l.match(/warn\(([a-z_]+)\)/);
        if (w && !cur.code && /#\[warn\(/.test(l)) cur.code = `rust:${w[1]}`;
    }
    flush();
    return out;
}

function parseGo(lines) {
    const out = [];
    for (const l of lines) {
        const m = l.match(/^([^ :]+\.go):([0-9]+):([0-9]+): (.*)$/);
        if (m) out.push(finding('error', m[1], m[2], m[3], '', m[4], '', ''));
    }
    return out;
}

function parseGeneric(lines) {
    const out = [];
    for (const l of lines) {
        if (!/(error|Error|ERROR|failed|FAILED)/.test(l)) continue;
        const m = l.match(/[A-Za-z0-9_.\/-]+\.[A-Za-z]+:[0-9]+(:[0-9]+)?/);
        if (!m || /^[0-9]/.test(m[0]) || /https?:/.test(m[0])) continue;
        const p = m[0].split(':');
        out.push(finding('error', p[0], p[1], p[2] || '', '', trim(l), '', ''));
    }
    return out;
}

function findings(text) {
    const lines = clean(text).split('\n');
    const all = [
        ...parseDartAnalyze(lines), ...parseFlutterTest(lines), ...parseTs(lines), ...parseEslint(lines),
        ...parseVitest(lines), ...parseJest(lines), ...parseCargo(lines), ...parseGo(lines),
    ];
    return all.length ? all : parseGeneric(lines);
}

function loadKb() {
    return fs.readFileSync(KB_FILE, 'utf8').split('\n')
        .filter((l) => l && !l.startsWith('#'))
        .map((l) => {
            const f = l.split('\t');
            return { id: f[0], kind: f[1], pat: f[2], why: f[3], fix: f[4], autofix: f[5], docs: f[6], group: f[7] };
        });
}

const rank = (s) => (s === 'error' || s === 'fail' ? 0 : s === 'warning' ? 1 : 2);
const norm = (m) => m.replace(/\$\{[^}]*\}/g, '').replace(/[0-9]+/g, 'N').replace(/ +/g, ' ').slice(0, 100);

function cluster(found, kb = loadKb()) {
    const map = new Map();
    for (const f of found) {
        let kid = '-';
        let key = '';
        if (f.code !== '-') {
            const row = kb.find((r) => r.kind === 'code' && r.pat === f.code);
            if (row) { kid = row.id; key = f.code; }
        }
        if (kid === '-') {
            for (const r of kb) {
                if (r.kind !== 'regex') continue;
                const m = f.msg.match(new RegExp(r.pat));
                if (m) { kid = r.id; key = r.group === 'match' ? m[0] : r.id; break; }
            }
        }
        if (!key) key = f.code !== '-' ? f.code : norm(f.msg);
        let c = map.get(key);
        if (!c) { c = { key, kid, count: 0, sev: 9, files: new Set(), examples: [], order: map.size }; map.set(key, c); }
        c.count++;
        c.sev = Math.min(c.sev, rank(f.sev));
        if (f.file !== '-') c.files.add(f.file);
        const ek = `${f.file}|${f.line}|${f.msg}`;
        let ex = c.examples.find((e) => e.ek === ek);
        if (!ex && c.examples.length < 3) { ex = { ek, f, n: 0, names: [] }; c.examples.push(ex); }
        if (ex) {
            ex.n++;
            if (ex.n <= 3 && f.name !== '-') ex.names.push(f.name);
        }
    }
    return [...map.values()].sort((a, b) => a.sev - b.sev || b.count - a.count || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
}

// clusterSummary(text) -> lines "key<TAB>count<TAB>files<TAB>kbid" (same shape as diag_cluster_summary)
function clusterSummary(text) {
    return cluster(findings(text)).map((c) => `${c.key}\t${c.count}\t${c.files.size}\t${c.kid}`);
}

function snippet(file, line, col) {
    if (file === '-' || line === '-' || /node_modules/.test(file)) return [];
    let src;
    try { src = fs.readFileSync(file, 'utf8').split('\n'); } catch { return []; }
    const text = (src[Number(line) - 1] || '').replace(/\t/g, ' ').slice(0, 140);
    if (!text) return [];
    const pad = ' '.repeat(String(line).length);
    const rows = [`        ${line} | ${text}`];
    if (col !== '-' && Number(col) > 0) rows.push(`        ${pad} | ${' '.repeat(Number(col) - 1)}^`);
    return rows;
}

function nodePm() {
    if (fs.existsSync('pnpm-lock.yaml')) return 'pnpm';
    if (fs.existsSync('yarn.lock')) return 'yarn';
    if (fs.existsSync('bun.lockb') || fs.existsSync('bun.lock')) return 'bun';
    return 'npm';
}

function resolveAutofix(tpl, hasErrors) {
    if (tpl === '@LINT_FIX@') {
        try {
            const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
            if (!/(eslint|ng lint)/.test((pkg.scripts && pkg.scripts.lint) || '')) return '';
        } catch { return ''; }
        return { yarn: 'yarn lint --fix', pnpm: 'pnpm run lint --fix', bun: 'bun run lint --fix' }[nodePm()] || 'npm run lint -- --fix';
    }
    if (tpl === 'dart fix --apply') return fs.existsSync('pubspec.yaml') ? tpl : '';
    if (tpl.startsWith('cargo')) return fs.existsSync('Cargo.toml') && !hasErrors ? tpl : '';
    return tpl;
}

const short = (s, n = 160) => s.slice(0, n);

// diagnoseStep(label, logPath) -> { text, autofix: [...] }
function diagnoseStep(label, logPath) {
    const raw = fs.readFileSync(logPath, 'utf8');
    const found = findings(raw);
    const lines = [''];
    const autofix = [];

    if (!found.length) {
        const tail = clean(raw).split('\n').filter((l) => l.trim()).slice(-15);
        lines.push(`FAIL ${label}   (no file/line could be extracted; last lines of the log)`, ...tail.map((l) => `    ${l}`), `    full log: ${logPath}`);
        return { text: lines.join('\n'), autofix };
    }

    const kb = loadKb();
    const clusters = cluster(found, kb);
    const hasErrors = found.some((f) => f.sev === 'error');
    const root = process.cwd();
    lines.push(`FAIL ${label}   (${found.length} finding${found.length === 1 ? '' : 's'}, ${clusters.length} distinct cause${clusters.length === 1 ? '' : 's'})   full log: ${logPath}`);

    clusters.slice(0, 5).forEach((c, i) => {
        const row = c.kid !== '-' ? kb.find((r) => r.id === c.kid) : null;
        let auto = '';
        let docs = '';
        if (row) {
            if (row.autofix !== '-') auto = resolveAutofix(row.autofix, hasErrors);
            docs = c.key.includes('/') ? '-' : row.docs.replace(/@CODE@/g, c.key.replace(/^rust:/, ''));
            if (auto && !autofix.includes(auto)) autofix.push(auto);
        }
        lines.push('', ` ${i + 1}) ${c.key.replace(/^rust:/, '')}  x${c.count}${c.files.size ? ` in ${c.files.size} file${c.files.size === 1 ? '' : 's'}` : ''}${auto ? '   [auto-fixable]' : ''}`);
        for (const ex of c.examples) {
            const f = ex.f;
            const file = f.file.startsWith(`${root}${path.sep}`) ? f.file.slice(root.length + 1) : f.file;
            lines.push(file !== '-' ? `    ${file}${f.line !== '-' ? `:${f.line}` : ''}${f.col !== '-' ? `:${f.col}` : ''}  ${short(f.msg)}` : `    ${short(f.msg)}`);
            if (ex.names.length) lines.push(`        tests: ${short(ex.names.join(' | ') + (ex.n > 3 ? ` (+${ex.n - 3} more)` : ''), 200)}`);
            lines.push(...snippet(f.file, f.line, f.col));
            if (f.detail !== '-') lines.push(...f.detail.split(SEP).slice(0, 6).map((d) => `        > ${d}`));
        }
        if (row) {
            lines.push(`      Why:  ${row.why}`, `      Fix:  ${row.fix}`);
            if (auto) lines.push(`      Auto: ${auto}   (xgem ci --fix runs this)`);
            if (docs && docs !== '-') lines.push(`      Docs: ${docs}`);
        } else {
            lines.push('      (no known fix for this one; the location and message above are the real problem)');
        }
    });
    if (clusters.length > 5) lines.push('', `    (+${clusters.length - 5} more distinct cause${clusters.length - 5 === 1 ? '' : 's'} in the full log)`);
    return { text: lines.join('\n'), autofix };
}

module.exports = { findings, cluster, clusterSummary, diagnoseStep };
