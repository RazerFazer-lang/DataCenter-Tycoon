// Jedes Texturbild nur einmal: Bilder, die in den .glb-Modellen eingebettet sind, landen einmal in
// assets/textures/shared/ und die Modelle verweisen per URI darauf. Godot lädt sie beim Import als
// gemeinsame Textur (eine Datei, ein Speicherplatz, Materialien lassen sich zusammenfassen).
// Die neuen Bilder werden mit Grafikkarten-Kompression importiert (BC7, Normalmaps BC5).
//
//   node tools/dedupe_glb_textures.js          (im Projektordner)
//
// Nach jedem Lauf der Blender-Generatoren erneut ausführen: Blender bettet die Bilder wieder ein.
// Die eingebetteten Bytes bleiben im .glb liegen (nicht mehr verwendet), damit ändert sich nichts an
// den Puffern und Zugriffen des Modells.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = process.cwd();
const MODELS = path.join(ROOT, 'assets', 'models');
const SHARED = path.join(ROOT, 'assets', 'textures', 'shared');
fs.mkdirSync(SHARED, { recursive: true });

const EXT = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

function importFile(name) {
  const normal = /(_nrm|_normal|normalmap|_nor)(\b|_|$)/i.test(name.replace(/\.[a-z]+$/, ''));
  return `[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=${normal ? 1 : 0}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/size_limit=0
detect_3d/compress_to=0
`;
}

function readGlb(buf) {
  if (buf.readUInt32LE(0) !== 0x46546c67) throw new Error('kein glb');
  let off = 12;
  const chunks = [];
  while (off < buf.length) {
    const len = buf.readUInt32LE(off);
    const type = buf.readUInt32LE(off + 4);
    chunks.push({ type, data: buf.slice(off + 8, off + 8 + len) });
    off += 8 + len;
  }
  return chunks;
}

function writeGlb(json, chunks) {
  let js = Buffer.from(JSON.stringify(json), 'utf8');
  const pad = (4 - (js.length % 4)) % 4;
  if (pad) js = Buffer.concat([js, Buffer.alloc(pad, 0x20)]);
  const parts = [];
  const head = (len, type) => { const h = Buffer.alloc(8); h.writeUInt32LE(len, 0); h.writeUInt32LE(type, 4); return h; };
  parts.push(head(js.length, 0x4e4f534a), js);
  for (const c of chunks.slice(1)) parts.push(head(c.data.length, c.type), c.data);
  const body = Buffer.concat(parts);
  const h = Buffer.alloc(12);
  h.writeUInt32LE(0x46546c67, 0); h.writeUInt32LE(2, 4); h.writeUInt32LE(12 + body.length, 8);
  return Buffer.concat([h, body]);
}

let models = 0, moved = 0, written = 0, removed = 0, savedBytes = 0;
for (const f of fs.readdirSync(MODELS)) {
  if (!f.endsWith('.glb')) continue;
  const p = path.join(MODELS, f);
  const buf = fs.readFileSync(p);
  const chunks = readGlb(buf);
  const json = JSON.parse(chunks[0].data.toString('utf8'));
  const bin = chunks[1] && chunks[1].type === 0x004e4942 ? chunks[1].data : null;
  if (!json.images || !bin) continue;
  let changed = false;
  json.images.forEach((img, idx) => {
    if (img.bufferView === undefined) return;
    const bv = json.bufferViews[img.bufferView];
    const bytes = bin.slice(bv.byteOffset || 0, (bv.byteOffset || 0) + bv.byteLength);
    const ext = EXT[img.mimeType] || 'png';
    const hash = crypto.createHash('sha1').update(bytes).digest('hex').slice(0, 10);
    const base = (img.name || ('bild' + idx)).replace(/[^A-Za-z0-9_-]/g, '_');
    const name = `${base}_${hash}.${ext}`;
    const target = path.join(SHARED, name);
    if (!fs.existsSync(target)) {
      fs.writeFileSync(target, bytes);
      fs.writeFileSync(target + '.import', importFile(name));
      written++;
    } else {
      savedBytes += bytes.length;
    }
    // Bisher von Godot herausgelöstes Einzelbild dieses Modells entfernen.
    const old = path.join(MODELS, `${f.replace(/\.glb$/, '')}_${img.name || ''}.${ext}`);
    for (const o of [old, old + '.import']) {
      if (img.name && fs.existsSync(o)) { fs.unlinkSync(o); removed++; }
    }
    json.images[idx] = { name: img.name, mimeType: img.mimeType, uri: `../textures/shared/${name}` };
    moved++;
    changed = true;
  });
  if (changed) {
    fs.writeFileSync(p, writeGlb(json, chunks));
    models++;
  }
}
console.log(`Modelle ${models}, Bilder ${moved}, neue gemeinsame Bilder ${written}, alte Dateien entfernt ${removed}, doppelt gespart ${(savedBytes / 1048576).toFixed(1)} MB`);
