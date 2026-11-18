import fs from 'node:fs';
import path from 'node:path';

export function toPosix(value) {
  return value.split(path.sep).join('/');
}

export function relFrom(root, abs) {
  return toPosix(path.relative(root, abs));
}

export function walkFiles(dir, predicate, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === '.godot') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(full, predicate, out);
    } else if (entry.isFile() && predicate(entry.name, full)) {
      out.push(full);
    }
  }
  return out;
}

export function posixJoin(...parts) {
  return parts
    .filter((part) => part !== '')
    .join('/')
    .replace(/\/+/g, '/');
}
