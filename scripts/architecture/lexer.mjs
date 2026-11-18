// GDScript 词法辅助：只做字符串字面量、静态 import 与 extends 的轻量解析。
// 这是词法级扫描，不构建完整 AST；注释中的内容不会被当作依赖。

export function scanStringLiterals(content) {
  const literals = [];
  const n = content.length;
  let i = 0;
  let line = 1;

  while (i < n) {
    const ch = content[i];
    if (ch === '\n') {
      line += 1;
      i += 1;
      continue;
    }
    if (ch === '#') {
      while (i < n && content[i] !== '\n') i += 1;
      continue;
    }
    if (ch !== '"' && ch !== "'") {
      i += 1;
      continue;
    }

    const quote = ch;
    const start = i;
    const startLine = line;
    const triple = content.startsWith(quote + quote + quote, i);
    const delim = triple ? quote + quote + quote : quote;
    i += delim.length;
    let value = '';

    while (i < n) {
      if (content.startsWith(delim, i)) {
        i += delim.length;
        break;
      }
      const c = content[i];
      if (c === '\\') {
        if (i + 1 < n) {
          if (content[i + 1] === '\n') line += 1;
          value += content[i + 1];
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }
      if (c === '\n') {
        if (!triple) break;
        line += 1;
      }
      value += c;
      i += 1;
    }

    literals.push({ value, line: startLine, start, end: i });
  }
  return literals;
}

export function extractResPaths(text) {
  return text.match(/res:\/\/[A-Za-z0-9_.\-\/]*/g) ?? [];
}

function importKindBefore(content, literalStart) {
  const lineStart = content.lastIndexOf('\n', literalStart - 1) + 1;
  const prefix = content.slice(lineStart, literalStart);
  if (/^\s*extends\s*$/.test(prefix)) return 'extends';

  let i = literalStart - 1;
  while (i >= 0 && /\s/.test(content[i])) i -= 1;
  if (content[i] !== '(') return null;
  i -= 1;
  while (i >= 0 && /\s/.test(content[i])) i -= 1;
  const end = i + 1;
  while (i >= 0 && /[A-Za-z0-9_]/.test(content[i])) i -= 1;
  const identifier = content.slice(i + 1, end);
  return identifier === 'load' || identifier === 'preload' ? identifier : null;
}

// 只识别静态字符串参数：preload("...")、load("...")、extends "..."。
// load(variable) 等动态调用没有字面量参数，无法在此静态验证。
export function extractStaticImports(content) {
  const imports = [];
  for (const literal of scanStringLiterals(content)) {
    const kind = importKindBefore(content, literal.start);
    if (!kind) continue;
    imports.push({ kind, value: literal.value, line: literal.line });
  }
  return imports;
}

export function parseExtendsBase(content) {
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const trimmed = lines[i].trim();
    if (trimmed === '' || trimmed.startsWith('#') || trimmed.startsWith('@')) continue;
    const match = trimmed.match(/^extends\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (match) return { base: match[1], line: i + 1 };
    if (trimmed.startsWith('extends')) return null;
    if (!trimmed.startsWith('class_name')) break;
  }
  return null;
}

export function countLines(content) {
  if (content.length === 0) return 0;
  const parts = content.split(/\r?\n/);
  if (content.endsWith('\n')) parts.pop();
  return parts.length;
}
