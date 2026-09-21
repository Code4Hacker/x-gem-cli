#!/bin/bash
# Regression test for xgem ci diagnosis: real tool output in fixtures/ci must
# keep clustering into the expected causes (bash engine, and the Windows
# engine when node is available).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export XGEM_HOME=$ROOT
. "$ROOT/lib/logger.sh"
. "$ROOT/lib/ci-diagnose.sh"

FIX="$ROOT/test/fixtures/ci"
fail=0
actual=$(mktemp)

for log in "$FIX"/*.log; do
    name=$(basename "$log" .log)
    diag_cluster_summary "$log" | sed "s|^|$name\t|"
done | sort > "$actual"

if ! diff <(grep -v '^#' "$FIX/expected.tsv" | sort) "$actual"; then
    echo "FAIL: bash diagnosis differs from test/fixtures/ci/expected.tsv"
    fail=1
fi

if command -v node >/dev/null 2>&1; then
    node "$ROOT/test/ci-diagnose-win.js" "$FIX" | sort > "$actual.win"
    if ! diff <(grep -v '^#' "$FIX/expected.tsv" | sort) "$actual.win"; then
        echo "FAIL: Windows engine diagnosis differs from expected.tsv"
        fail=1
    fi
fi

rm -f "$actual" "$actual.win"
[ "$fail" -eq 0 ] && echo "ci-diagnose: all fixtures match"
exit "$fail"
