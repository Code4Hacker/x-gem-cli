// xgem Windows engine logger — mirrors lib/logger.sh's levels/colors.
// Manual ANSI codes (no dependency): Windows 10+ cmd.exe and PowerShell
// both support ANSI escapes natively, and we skip color entirely when
// stdout isn't a TTY (e.g. piped output).

const isTTY = process.stdout.isTTY === true;

const colors = {
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[1;34m',
    cyan: '\x1b[1;36m',
    gray: '\x1b[90m',
    reset: '\x1b[0m',
};

function paint(color, text) {
    return isTTY ? `${colors[color]}${text}${colors.reset}` : text;
}

const VERBOSE = process.env.XGEM_VERBOSE === '1';

function logInfo(msg) { console.log(`${paint('blue', '[INFO]')} ${msg}`); }
function logSuccess(msg) { console.log(`${paint('green', '[ OK ]')} ${msg}`); }
function logWarn(msg) { console.error(`${paint('yellow', '[WARN]')} ${msg}`); }
function logError(msg) { console.error(`${paint('red', '[FAIL]')} ${msg}`); }
function logDebug(msg) { if (VERBOSE) console.error(`${paint('gray', `[DBG ] ${msg}`)}`); }

function die(msg, code = 1) {
    logError(msg);
    process.exit(code);
}

module.exports = { paint, logInfo, logSuccess, logWarn, logError, logDebug, die, isTTY };
