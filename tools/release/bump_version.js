// Setzt die Version in allen Dateien und trägt den Changelog ein (Teil von release.ps1).
// Aufruf: node tools/release/bump_version.js <version> <notes.json> [<datum JJJJ-MM-TT>]
// notes.json: { "title": "...", "items": ["[TAG] Text", ...], "roadmap": "Kurztext für die Launcher-Roadmap" }
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const [version, notesPath, dateArg] = process.argv.slice(2);
if (!/^\d+\.\d+\.\d+$/.test(version || '') || !notesPath) {
  console.error('Aufruf: node bump_version.js <X.Y.Z> <notes.json> [datum]');
  process.exit(2);
}
const notes = JSON.parse(fs.readFileSync(notesPath, 'utf8'));
if (!notes.title || !Array.isArray(notes.items) || notes.items.length === 0) {
  console.error('notes.json braucht "title" und "items".');
  process.exit(2);
}
const date = dateArg || new Date().toISOString().slice(0, 10);
const rel = p => path.join(ROOT, p);
const read = p => fs.readFileSync(rel(p), 'utf8');
const write = (p, t) => fs.writeFileSync(rel(p), t);

// Bisherige Version aus project.godot
const proj = read('project.godot');
const m = proj.match(/config\/version="(\d+\.\d+\.\d+)"/);
if (!m) { console.error('Keine Version in project.godot'); process.exit(1); }
const old = m[1];
if (old === version) { console.log('Version ist schon ' + version + ', nur Changelog prüfen.'); }

function swap(file, a, b, count) {
  const t = read(file);
  const n = t.split(a).length - 1;
  if (n !== count) throw new Error(`${file}: "${a}" ${n}x statt ${count}x`);
  write(file, t.split(a).join(b));
}
if (old !== version) {
  swap('export_presets.cfg', old + '.0', version + '.0', 2);
  swap('launcher/DataCenterLauncher.csproj', old, version, 3);
  swap('launcher/LauncherConfig.cs', `"${old}"`, `"${version}"`, 1);
  swap('project.godot', `config/version="${old}"`, `config/version="${version}"`, 1);
}

const saveJson = (file, obj) => {
  const before = read(file);
  let s = JSON.stringify(obj, null, 2) + (before.endsWith('\n') ? '\n' : '');
  if (before.includes('\r\n')) s = s.replace(/\n/g, '\r\n');
  write(file, s);
};

const v = JSON.parse(read('version.json'));
v.version = version;
v.launcher_version = version;
v.codename = `v${version} ${notes.title}`;
v.release_date = date;
v.changelog = (v.changelog || []).filter(c => c.version !== 'v' + version);
v.changelog.unshift({ version: 'v' + version, date, title: `Update ${version}: ${notes.title}`, items: notes.items });
saveJson('version.json', v);

const r = JSON.parse(read('roadmap.json'));
r.updated = date;
const done = r.columns.find(c => c.id === 'done');
done.items = done.items.filter(i => i.version !== 'v' + version);
done.items.unshift({ tag: 'neu', version: 'v' + version, title: notes.title, desc: notes.roadmap || notes.items[0].replace(/^\[[^\]]*\]\s*/, '') });
// Was jetzt fertig ist, steht nicht mehr unter „In Arbeit“.
const prog = r.columns.find(c => c.id === 'in_progress');
if (prog) prog.items = prog.items.filter(i => i.title !== notes.title);
saveJson('roadmap.json', r);

console.log(`Version ${old} -> ${version}, Changelog „${notes.title}“ mit ${notes.items.length} Punkten.`);
