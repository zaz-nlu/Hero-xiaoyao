import fs from 'node:fs';
import path from 'node:path';
import { relFrom, walkFiles } from './fsutil.mjs';
import { defaultConfig, validateConfig } from './config.mjs';
import { analyzeDependencies, classifyGodotPath } from './dependencies.mjs';
import { countLines, parseExtendsBase } from './lexer.mjs';
import { validateProjectAndResources } from './resources.mjs';

function collectProductionFiles(root, godotRoot, config) {
  const files = [];
  for (const dirName of config.productionDirs) {
    const base = path.join(godotRoot, dirName);
    for (const abs of walkFiles(base, (name) => name.endsWith('.gd'))) {
      const content = fs.readFileSync(abs, 'utf8');
      files.push({
        rel: relFrom(root, abs),
        godotRel: relFrom(godotRoot, abs),
        content,
        lines: countLines(content),
      });
    }
  }
  files.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
  return files;
}

function checkLineBudgets(files, config, addViolation) {
  for (const file of files) {
    const hasLegacy = Object.prototype.hasOwnProperty.call(
      config.legacyLineBudgets,
      file.rel,
    );
    if (!hasLegacy) {
      if (file.lines > config.defaultMaxLines) {
        addViolation(
          'line-budget',
          file.rel,
          0,
          `新文件行数 ${file.lines} 超过上限 ${config.defaultMaxLines}`,
        );
      }
      continue;
    }

    const budget = config.legacyLineBudgets[file.rel];
    if (file.lines > budget) {
      addViolation(
        'legacy-line-budget',
        file.rel,
        0,
        `超出该文件精确行数预算：${file.lines} > ${budget}`,
      );
    } else if (file.lines < budget) {
      addViolation(
        'stale-line-budget',
        file.rel,
        0,
        `预算 ${budget} 高于当前 ${file.lines} 行；请人工下调或删除该例外`,
      );
    }
  }

  const productionRels = new Set(files.map((file) => file.rel));
  for (const rel of Object.keys(config.legacyLineBudgets)) {
    if (productionRels.has(rel)) continue;
    addViolation(
      'stale-line-budget-entry',
      'architecture.config.json',
      0,
      `legacyLineBudgets 指向的文件不存在或不在生产目录: ${rel}`,
    );
  }
}

function checkCoreBaseClasses(files, config, addViolation) {
  for (const file of files) {
    if (classifyGodotPath(file.godotRel, config).kind !== 'core') continue;
    const base = parseExtendsBase(file.content);
    if (!base) continue;
    if (!config.coreForbiddenBaseClasses.includes(base.base)) continue;
    addViolation(
      'core-scene-type',
      file.rel,
      base.line,
      `core 脚本不能 extends 场景类型 ${base.base}（RefCounted/Resource 允许）`,
    );
  }
}

export function inspectProject(root, configInput = {}) {
  const config = { ...defaultConfig(), ...(configInput ?? {}) };
  const godotRoot = path.join(root, config.godotDir);
  const violations = [];
  const warnings = [];

  const addViolation = (rule, file, line, message) => {
    violations.push({ rule, file, line: line || 0, message });
  };

  validateConfig(config, addViolation);

  const files = collectProductionFiles(root, godotRoot, config);
  checkCoreBaseClasses(files, config, addViolation);
  checkLineBudgets(files, config, addViolation);

  const { edges, cycles } = analyzeDependencies(
    files,
    config,
    addViolation,
    warnings,
  );
  const resourceStats = validateProjectAndResources({
    root,
    godotRoot,
    config,
    files,
    addViolation,
    warnings,
  });

  return {
    violations,
    warnings,
    stats: {
      productionGdFiles: files.length,
      dependencyEdges: edges.length,
      scenes: resourceStats.scenes,
      contentJsonFiles: resourceStats.contentJsonFiles,
      resourceRefs: resourceStats.resourceRefs,
      legacyLineBudgets: Object.keys(config.legacyLineBudgets).length,
      legacyCrossFeatureEdges: config.legacyCrossFeatureEdges.length,
      allowedMissingResources: config.allowedMissingResources.length,
      cycles: cycles.length,
    },
  };
}
