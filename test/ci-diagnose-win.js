// Prints "fixture<TAB>key<TAB>count<TAB>files<TAB>kbid" for every log in the
// fixtures dir, using the Windows engine's parser (run by test/ci-diagnose.sh).
const fs = require('node:fs');
const path = require('node:path');
const { clusterSummary } = require('../lib-win/ci-diagnose');

const dir = process.argv[2];
for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.log'))) {
    const text = fs.readFileSync(path.join(dir, f), 'utf8');
    for (const line of clusterSummary(text)) console.log(`${f.replace(/\.log$/, '')}\t${line}`);
}
