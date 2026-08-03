// xgem Windows engine generic scaffold — mirrors lib/scaffold.sh, but
// writes/runs .mjs templates instead of .sh. `swift` is intentionally
// omitted: there's no meaningful Windows Swift toolchain story.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');

const ALL_FRAMEWORKS = ['flutter', 'node', 'python', 'react', 'vue', 'angular', 'next', 'go', 'rust', 'docker'];

const FRAMEWORK_SCRIPTS = {
    flutter: ['hard-clean', 'build', 'build-runner'],
    node: ['hard-clean', 'build', 'start'],
    python: ['hard-clean', 'install'],
    react: ['hard-clean', 'build', 'dev'],
    vue: ['hard-clean', 'build', 'dev'],
    angular: ['hard-clean', 'build', 'dev'],
    next: ['hard-clean', 'build', 'dev'],
    go: ['hard-clean', 'build'],
    rust: ['hard-clean', 'build'],
    docker: ['hard-clean', 'build-up'],
};

const WEB_FRAMEWORKS = ['node', 'react', 'vue', 'angular', 'next'];

// Only offer lint/test automation when the current directory's
// package.json actually declares those scripts, instead of always
// generating scripts that fail with "Missing script" on projects that
// don't have them.
function packageJsonHasScript(scriptName) {
    try {
        const pkg = JSON.parse(require('node:fs').readFileSync('package.json', 'utf8'));
        return Boolean(pkg.scripts && pkg.scripts[scriptName]);
    } catch {
        return false;
    }
}

function frameworkScripts(fw) {
    const base = FRAMEWORK_SCRIPTS[fw];
    if (!base) return null;
    if (!WEB_FRAMEWORKS.includes(fw)) return base;

    const scripts = [...base];
    if (packageJsonHasScript('lint')) scripts.push('lint');
    if (packageJsonHasScript('test')) scripts.push('test');
    return scripts;
}

function templateDir(fw) {
    const templatesRoot = path.join(__dirname, '..', 'templates-win');
    if (fw === 'react' || fw === 'vue' || fw === 'angular' || fw === 'next') {
        return path.join(templatesRoot, 'webframework');
    }
    return path.join(templatesRoot, fw);
}

function injectTemplates(fw, configDir) {
    const scripts = frameworkScripts(fw);
    if (!scripts) die(`Unknown framework '${fw}'.`);

    const srcDir = templateDir(fw);
    const destDir = path.join(configDir, fw);
    fs.mkdirSync(destDir, { recursive: true });

    for (const script of scripts) {
        const src = path.join(srcDir, `${script}.mjs.tmpl`);
        const dest = path.join(destDir, `${script}.mjs`);
        if (!fs.existsSync(src)) {
            logWarn(`Missing template ${src}, skipping.`);
            continue;
        }
        const content = fs.readFileSync(src, 'utf8').replace(/__FRAMEWORK__/g, fw);
        fs.writeFileSync(dest, content);
    }
}

function runScript(fw, script, configDir) {
    const target = path.join(configDir, fw, `${script}.mjs`);
    if (fs.existsSync(target)) {
        logInfo(`Running script '${script}' for ${fw}...`);
        const result = spawnSync(process.execPath, [target], { stdio: 'inherit' });
        process.exitCode = result.status ?? 0;
    } else {
        logError(`Script not found at ${target}`);
        const fwDir = path.join(configDir, fw);
        if (fs.existsSync(fwDir)) {
            console.log(`Available scripts in '${fw}':`);
            for (const f of fs.readdirSync(fwDir)) {
                console.log(`  - ${f.replace(/\.mjs$/, '')}`);
            }
        }
        process.exitCode = 1;
    }
}

function getRemainingFrameworks(configDir) {
    return ALL_FRAMEWORKS.filter((fw) => !fs.existsSync(path.join(configDir, fw)));
}

module.exports = { ALL_FRAMEWORKS, frameworkScripts, injectTemplates, runScript, getRemainingFrameworks };
