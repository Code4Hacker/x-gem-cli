// xgem's global (cross-project) registry — port of lib/registry.sh. Same
// plain newline-delimited path file, so a dual-boot user's registry is
// readable from either platform.

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const REGISTRY_FILE = process.env.XGEM_REGISTRY_FILE || path.join(os.homedir(), '.xgem', 'projects');

function readLines() {
    if (!fs.existsSync(REGISTRY_FILE)) return [];
    return fs.readFileSync(REGISTRY_FILE, 'utf8').split(/\r?\n/).filter(Boolean);
}

function writeLines(lines) {
    fs.mkdirSync(path.dirname(REGISTRY_FILE), { recursive: true });
    fs.writeFileSync(REGISTRY_FILE, lines.length ? lines.join('\n') + '\n' : '');
}

function registryAdd(projectPath) {
    const lines = readLines();
    if (!lines.includes(projectPath)) {
        lines.push(projectPath);
        writeLines(lines);
    }
}

function registryRemove(projectPath) {
    writeLines(readLines().filter((l) => l !== projectPath));
}

// registryList(configDir) — returns live project paths, pruning (and
// rewriting the registry for) any entry that no longer exists or is no
// longer xgem-tracked.
function registryList(configDir) {
    const lines = readLines();
    const live = lines.filter((p) => fs.existsSync(path.join(p, configDir)));
    if (live.length !== lines.length) writeLines(live);
    return live;
}

module.exports = { registryAdd, registryRemove, registryList };
