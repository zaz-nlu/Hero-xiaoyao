import { posixJoin } from './fsutil.mjs';
import {
  extractResPaths,
  extractStaticImports,
  scanStringLiterals,
} from './lexer.mjs';

export function classifyGodotPath(godotRel, config) {
  const segments = godotRel.split('/');
  const top = segments[0];
  if (!config.productionDirs.includes(top)) {
    return { kind: 'outside', feature: null };
  }
  if (top === 'features') {
    return { kind: 'feature', feature: segments[1] ?? '' };
  }
  return { kind: top, feature: null };
}

function collectEdges(fileRel, godotRel, content, config, addViolation) {
  const edges = [];
  const classification = classifyGodotPath(godotRel, config);

  for (const literal of scanStringLiterals(content)) {
    for (const resPath of extractResPaths(literal.value)) {
      if (!resPath.endsWith('.gd')) continue;

      const targetGodotRel = resPath.slice('res://'.length);
      const target = classifyGodotPath(targetGodotRel, config);
      if (target.kind === 'outside') {
        addViolation(
          'gd-outside-production-roots',
          fileRel,
          literal.line,
          `GDScript 引用必须位于 app/core/features/shared 之下: ${resPath}`,
        );
        continue;
      }

      edges.push({
        fromRel: fileRel,
        toRel: posixJoin(config.godotDir, targetGodotRel),
        targetPath: resPath,
        line: literal.line,
        fromKind: classification.kind,
        toKind: target.kind,
        fromFeature: classification.feature,
        toFeature: target.feature,
      });
    }
  }
  return edges;
}

function checkStaticImportPaths(fileRel, content, addViolation) {
  for (const entry of extractStaticImports(content)) {
    if (entry.value.startsWith('res://')) continue;
    addViolation(
      'non-res-import',
      fileRel,
      entry.line,
      `${entry.kind} 的静态路径必须使用完整 res://: ${entry.value}`,
    );
  }
}

function legacyEdgeKey(entry) {
  return `${entry.fromPath}:${entry.line}:${entry.toPath}`;
}

function isCrossFeatureAllowed(edge, config, matchedLegacy, warnings) {
  const allowed = config.allowedCrossFeatureEdges.find(
    (entry) => entry.from === edge.fromFeature && entry.to === edge.toFeature,
  );
  if (allowed) return true;

  const key = `${edge.fromRel}:${edge.line}:${edge.toRel}`;
  const legacy = config.legacyCrossFeatureEdges.find(
    (entry) => legacyEdgeKey(entry) === key,
  );
  if (!legacy) return false;

  matchedLegacy.add(key);
  warnings.push({
    file: edge.fromRel,
    line: edge.line,
    message: `legacy cross-feature edge (${edge.fromFeature} -> ${edge.toFeature}); ${legacy.reason}`,
  });
  return true;
}

function isDirectionAllowed(edge, config, matchedLegacy, warnings) {
  switch (edge.fromKind) {
    case 'app':
      // 分类器对 features/<name> 返回 kind=feature（不是 features）。
      return ['app', 'core', 'feature', 'shared'].includes(edge.toKind);
    case 'core':
      return edge.toKind === 'core';
    case 'shared':
      return edge.toKind === 'shared' || edge.toKind === 'core';
    case 'feature':
      if (edge.toKind === 'core' || edge.toKind === 'shared') return true;
      if (edge.toKind !== 'feature') return false;
      if (edge.fromFeature === edge.toFeature) return true;
      return isCrossFeatureAllowed(edge, config, matchedLegacy, warnings);
    default:
      return true;
  }
}

function checkDirections(edges, config, addViolation, warnings) {
  const matchedLegacy = new Set();
  for (const edge of edges) {
    if (isDirectionAllowed(edge, config, matchedLegacy, warnings)) continue;
    const fromLabel = edge.fromKind === 'feature'
      ? `feature:${edge.fromFeature}`
      : edge.fromKind;
    const toLabel = edge.toKind === 'feature'
      ? `feature:${edge.toFeature}`
      : edge.toKind;
    addViolation(
      'dependency-direction',
      edge.fromRel,
      edge.line,
      `${fromLabel} -> ${toLabel} 不被允许（目标 ${edge.targetPath}）`,
    );
  }

  for (const entry of config.legacyCrossFeatureEdges) {
    if (matchedLegacy.has(legacyEdgeKey(entry))) continue;
    addViolation(
      'stale-legacy-cross-feature-edge',
      'architecture.config.json',
      0,
      `legacyCrossFeatureEdges 未匹配到实际引用，请删除: ${entry.fromPath}:${entry.line} -> ${entry.toPath}`,
    );
  }
}

function findCycles(edges) {
  const adjacency = new Map();
  for (const edge of edges) {
    // 自引用（如 load("res://core/unit.gd") 用于类型判断）不构成跨模块循环。
    if (edge.fromRel === edge.toRel) continue;
    if (!adjacency.has(edge.fromRel)) adjacency.set(edge.fromRel, []);
    adjacency.get(edge.fromRel).push(edge);
  }

  const color = new Map();
  const stack = [];
  const cycles = [];
  const seen = new Set();

  const visit = (node) => {
    color.set(node, 1);
    stack.push(node);
    for (const edge of adjacency.get(node) ?? []) {
      const next = edge.toRel;
      const state = color.get(next) ?? 0;
      if (state === 0) {
        visit(next);
      } else if (state === 1) {
        const start = stack.indexOf(next);
        if (start >= 0) {
          const cycle = stack.slice(start).concat(next);
          const key = cycle.join(' -> ');
          if (!seen.has(key)) {
            seen.add(key);
            cycles.push(cycle);
          }
        }
      }
    }
    stack.pop();
    color.set(node, 2);
  };

  for (const node of adjacency.keys()) {
    if ((color.get(node) ?? 0) === 0) visit(node);
  }
  return cycles;
}

export function analyzeDependencies(files, config, addViolation, warnings) {
  const edges = [];
  for (const file of files) {
    edges.push(...collectEdges(file.rel, file.godotRel, file.content, config, addViolation));
    checkStaticImportPaths(file.rel, file.content, addViolation);
  }

  checkDirections(edges, config, addViolation, warnings);

  const cycles = findCycles(edges);
  for (const cycle of cycles) {
    addViolation(
      'dependency-cycle',
      cycle[0],
      0,
      `检测到循环依赖: ${cycle.join(' -> ')}`,
    );
  }

  return { edges, cycles };
}
