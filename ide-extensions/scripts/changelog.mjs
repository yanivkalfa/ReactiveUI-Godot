#!/usr/bin/env node
/**
 * Centralized changelog management for the GUITKX IDE extensions.
 *
 * Source of truth: ide-extensions/changelog.json
 * Per-IDE CHANGELOG.md files are generated from this file by the publish workflow.
 *
 * Commands:
 *   add              — Append a changelog entry
 *   extract          — Generate per-IDE CHANGELOG.md (stdout or --out)
 *   extract-overview — Generate VS Marketplace overview.md (stdout or --out)
 *   import           — Import entries from an existing markdown changelog
 *
 * Run `node ide-extensions/scripts/changelog.mjs` with no args for full usage.
 *
 * Ported from ReactiveUIToolKit's scripts/changelog.mjs (retargeted to ide-extensions/).
 */
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const IDE_ROOT = resolve(__dirname, '..'); // ide-extensions/
const CHANGELOG_PATH = resolve(IDE_ROOT, 'changelog.json');
const KNOWN_IDES = ['vscode', 'vs2022'];

// ── helpers ──────────────────────────────────────────────────────────────────

function readChangelog() {
  try {
    return JSON.parse(readFileSync(CHANGELOG_PATH, 'utf8'));
  } catch {
    return { entries: [] };
  }
}

function writeChangelog(data) {
  writeFileSync(CHANGELOG_PATH, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith('--')) {
        args[key] = next;
        i++;
      } else {
        args[key] = true;
      }
    }
  }
  return args;
}

function output(text, args) {
  if (args.out) {
    writeFileSync(resolve(args.out), text, 'utf8');
    console.error(`Wrote ${resolve(args.out)}`);
  } else {
    process.stdout.write(text);
  }
}

// ── add ──────────────────────────────────────────────────────────────────────

/**
 * Detect tell-tale signs of CP1252→UTF-8 mojibake in a message string.
 * On Windows, invoking this script through PowerShell or cmd transcodes argv
 * to the active code page (typically CP1252) before Node receives it, so
 * characters like `—`, `’`, curly quotes, and ellipsis arrive corrupted
 * (`â€"`, `â€™`, `â€¦`, …). We refuse to write such content to the JSON.
 *
 * Also catches the silent truncation when a message contains `"…"` (PowerShell
 * strips embedded double-quotes from argv): use --message-file instead.
 */
function detectArgvCorruption(message) {
  if (/Â[-¿]/.test(message)
   || /Ã[-¿]/.test(message)
   || /â€/.test(message)
   || /â‚/.test(message)
   || /ï¿½/.test(message)
  ) {
    return 'looks like CP1252→UTF-8 mojibake (e.g. "â€"" instead of "—"). '
      + 'PowerShell/cmd transcoded argv. Use --message-file <utf8-file> instead.';
  }
  if (message.includes('�')) {
    return 'contains the Unicode replacement character (U+FFFD). '
      + 'Use --message-file <utf8-file> instead.';
  }
  return null;
}

/** Read message text from --message-file (UTF-8) or --message (argv). */
function readMessageArg(args) {
  if (args['message-file']) {
    const p = resolve(args['message-file']);
    if (!existsSync(p)) {
      console.error(`Message file not found: ${p}`);
      process.exit(1);
    }
    return readFileSync(p, 'utf8').replace(/\r\n/g, '\n').replace(/\n+$/, '');
  }
  if (args.message && args.message !== true) {
    return args.message;
  }
  return null;
}

function cmdAdd(args) {
  const scope = args.scope;
  const message = readMessageArg(args);

  if (!scope || !message) {
    console.error(
      'Usage: add --scope <shared|vscode|vs2022>\n' +
      '           (--message "text" | --message-file <path>)\n' +
      '           [--vscode X.Y.Z] [--vs2022 X.Y.Z] [--date YYYY-MM-DD]\n' +
      '\n' +
      'Prefer --message-file for any non-ASCII content (em-dashes, quotes, etc.) —\n' +
      'PowerShell/cmd transcode argv through the active code page and corrupt UTF-8.'
    );
    process.exit(1);
  }

  const corruption = detectArgvCorruption(message);
  if (corruption) {
    console.error(`Refusing to add: message ${corruption}`);
    process.exit(1);
  }

  if (scope !== 'shared' && !KNOWN_IDES.includes(scope)) {
    console.error(`Unknown scope: ${scope}. Use: shared, ${KNOWN_IDES.join(', ')}`);
    process.exit(1);
  }

  const versions = {};
  for (const ide of KNOWN_IDES) {
    if (args[ide]) versions[ide] = args[ide];
  }
  if (Object.keys(versions).length === 0) {
    console.error('Provide at least one IDE version: --vscode X.Y.Z, --vs2022 X.Y.Z');
    process.exit(1);
  }

  const date = args.date || today();
  const data = readChangelog();

  let entry = data.entries.find(e =>
    e.date === date &&
    Object.entries(versions).every(([k, v]) => e.versions[k] === v)
  );

  if (!entry) {
    entry = { date, versions };
    data.entries.unshift(entry); // newest first
  }

  if (!entry[scope]) entry[scope] = [];
  entry[scope].push(message);

  writeChangelog(data);
  const verStr = Object.entries(versions).map(([k, v]) => `${k} ${v}`).join(', ');
  console.error(`Added to ${scope} in ${date} entry (${verStr})`);
}

// ── extract ──────────────────────────────────────────────────────────────────

/**
 * Render the per-IDE CHANGELOG.md text for `ide` from the changelog data.
 * The SAME rendering is used by `extract` (writes it) and `verify` (checks it) —
 * one implementation, so the two can never drift from each other the way the
 * committed CHANGELOG.md files drifted from changelog.json (see `verify`'s doc
 * comment for the incident this guards against).
 */
function renderChangelog(data, ide, version) {
  const relevant = data.entries.filter(e => e.versions && e.versions[ide]);
  const filtered = version ? relevant.filter(e => e.versions[ide] === version) : relevant;

  const lines = ['# Changelog', ''];
  for (const entry of filtered) {
    const ver = entry.versions[ide];
    lines.push(`## [${ver}] - ${entry.date}`);
    const messages = [...(entry.shared || []), ...(entry[ide] || [])];
    for (const msg of messages) lines.push(`- ${msg}`);
    lines.push('');
  }
  return lines.join('\n');
}

function cmdExtract(args) {
  const ide = args.ide;
  if (!ide) {
    console.error('Usage: extract --ide <vscode|vs2022> [--version X.Y.Z] [--out file]');
    process.exit(1);
  }

  const data = readChangelog();
  output(renderChangelog(data, ide, args.version), args);
}

// ── verify ───────────────────────────────────────────────────────────────────

/**
 * The committed CHANGELOG.md for each IDE, relative to IDE_ROOT (ide-extensions/).
 * `vs2022`'s is never regenerated by any CI/publish step today (only vscode's is,
 * in `.github/workflows/publish.yml`), so it is exactly as prone to drift — this
 * check covers both the same way.
 */
const CHANGELOG_FILES = {
  vscode: 'vscode/CHANGELOG.md',
  vs2022: 'visual-studio/CHANGELOG.md',
};

/**
 * Guards the exact failure mode that shipped GUITKX 0.6.0-0.8.4: engineers bumped
 * `ide-extensions/vscode/CHANGELOG.md` by hand (or added entries to it without a
 * matching `changelog.mjs add`), so `changelog.json` — the documented single
 * source of truth — silently fell 14 versions behind what was actually released.
 * The Marketplace "Changelog" tab reads the CHANGELOG.md bundled into whatever
 * VSIX was last actually published, which is regenerated FROM changelog.json at
 * publish time — so a stale changelog.json means the next publish ships a
 * changelog that is wrong (or the discrepancy is masked until publish exposes it).
 *
 * Run in CI on every push/PR (see `.github/workflows/ide-extensions.yml`): fails
 * loudly, with a diff, the moment changelog.json and a committed CHANGELOG.md
 * disagree — instead of silently at the next publish.
 */
function cmdVerify(args) {
  const ides = args.ide ? [args.ide] : Object.keys(CHANGELOG_FILES);
  const data = readChangelog();
  let ok = true;

  for (const ide of ides) {
    const relPath = CHANGELOG_FILES[ide];
    if (!relPath) {
      console.error(`Unknown IDE for verify: ${ide}. Use: ${Object.keys(CHANGELOG_FILES).join(', ')}`);
      process.exit(1);
    }

    const filePath = resolve(IDE_ROOT, relPath);
    const expected = renderChangelog(data, ide);

    if (!existsSync(filePath)) {
      console.error(`✗ ${relPath}: missing (expected it to be generated from changelog.json)`);
      ok = false;
      continue;
    }

    const actual = readFileSync(filePath, 'utf8').replace(/\r\n/g, '\n');
    if (actual.trimEnd() !== expected.trimEnd()) {
      console.error(`✗ ${relPath} is out of sync with changelog.json.`);
      console.error(`  Regenerate it: node ide-extensions/scripts/changelog.mjs extract --ide ${ide} --out ide-extensions/${relPath}`);
      console.error(`  (If changelog.json itself is missing entries, add them first with the 'add' command —`);
      console.error(`   never hand-edit ${relPath}.)`);
      ok = false;
    } else {
      console.error(`✓ ${relPath} matches changelog.json`);
    }
  }

  if (!ok) {
    console.error('\nchangelog verify FAILED — see above.');
    process.exit(1);
  }
  console.error('\nchangelog verify OK.');
}

// ── extract-overview ─────────────────────────────────────────────────────────

function cmdExtractOverview(args) {
  const ide = args.ide;
  const template = args.template;

  if (!ide || !template) {
    console.error('Usage: extract-overview --ide <vs2022> --template <path> [--out file]');
    process.exit(1);
  }

  const templatePath = resolve(template);
  if (!existsSync(templatePath)) {
    console.error(`Template not found: ${templatePath}`);
    process.exit(1);
  }

  const data = readChangelog();
  const relevant = data.entries.filter(e => e.versions && e.versions[ide]);

  const changelogLines = ['## Changelog', ''];
  for (const entry of relevant) {
    const ver = entry.versions[ide];
    changelogLines.push(`### [${ver}] - ${entry.date}`);
    const messages = [...(entry.shared || []), ...(entry[ide] || [])];
    for (const msg of messages) changelogLines.push(`- ${msg}`);
    changelogLines.push('');
  }

  const templateContent = readFileSync(templatePath, 'utf8').trimEnd();
  output(templateContent + '\n\n' + changelogLines.join('\n'), args);
}

// ── import ───────────────────────────────────────────────────────────────────

function cmdImport(args) {
  const ide = args.ide;
  const file = args.file;
  if (!ide || !file) {
    console.error('Usage: import --ide <vscode|vs2022> --file <path-to-CHANGELOG.md>');
    process.exit(1);
  }

  const filePath = resolve(file);
  if (!existsSync(filePath)) {
    console.error(`File not found: ${filePath}`);
    process.exit(1);
  }

  const content = readFileSync(filePath, 'utf8');
  const data = readChangelog();
  const SKIP = new Set(['skip', 'skip-no-new-entry', 'already set', 're-publish']);
  const versionRe = /^#{2,3}\s*\[([^\]]+)\]\s*-?\s*(\d{4}-\d{2}-\d{2})?/;
  let curVer = null, curDate = null;

  for (const line of content.split('\n')) {
    const m = line.match(versionRe);
    if (m) { curVer = m[1]; curDate = m[2] || 'unknown'; continue; }
    if (curVer && line.startsWith('- ')) {
      const msg = line.slice(2).trim();
      if (!msg || SKIP.has(msg)) continue;
      let entry = data.entries.find(e => e.versions && e.versions[ide] === curVer);
      if (!entry) { entry = { date: curDate, versions: { [ide]: curVer } }; data.entries.push(entry); }
      if (!entry[ide]) entry[ide] = [];
      if (!entry[ide].includes(msg)) entry[ide].push(msg);
    }
  }

  data.entries.sort((a, b) => {
    const da = a.date === 'unknown' ? '0000-00-00' : a.date;
    const db = b.date === 'unknown' ? '0000-00-00' : b.date;
    if (da !== db) return da > db ? -1 : 1;
    const aMax = Math.max(...Object.values(a.versions).map(v => parseFloat(v.split('.').pop()) || 0));
    const bMax = Math.max(...Object.values(b.versions).map(v => parseFloat(v.split('.').pop()) || 0));
    return bMax - aMax;
  });

  writeChangelog(data);
  const count = data.entries.filter(e => e.versions && e.versions[ide]).length;
  console.error(`Imported ${count} ${ide} entries from ${file}`);
}

// ── main ─────────────────────────────────────────────────────────────────────

const [command, ...rest] = process.argv.slice(2);
const args = parseArgs(rest);

switch (command) {
  case 'add':              cmdAdd(args); break;
  case 'extract':          cmdExtract(args); break;
  case 'extract-overview': cmdExtractOverview(args); break;
  case 'import':           cmdImport(args); break;
  case 'verify':           cmdVerify(args); break;
  default:
    console.log(
`Usage: node ide-extensions/scripts/changelog.mjs <command> [options]

Commands:
  add              Add a changelog entry
  extract          Generate per-IDE CHANGELOG.md
  extract-overview Generate overview.md with changelog section
  import           Import entries from existing markdown changelog

Examples:
  add --scope shared --message "Fix: server crash" --vscode 0.1.1 --vs2022 0.1.1
  add --scope shared --message-file CHANGES.txt --vscode 0.2.0 --vs2022 0.2.0
  add --scope vscode --message "Fix: debounce" --vscode 0.1.1
  extract --ide vscode --out ide-extensions/vscode/CHANGELOG.md
  extract-overview --ide vs2022 --template ide-extensions/visual-studio/GuitkxVsix/overview-template.md --out overview.md
  import --ide vscode --file ide-extensions/vscode/CHANGELOG.md

Tips:
  • Prefer --message-file for any non-ASCII content (em-dashes, quotes, code chars).
    PowerShell/cmd on Windows transcode argv through CP1252 and strip embedded quotes —
    --message-file reads UTF-8 verbatim and avoids both pitfalls.`
    );
}
