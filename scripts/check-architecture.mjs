#!/usr/bin/env node
// 架构检查入口：只负责 CLI。规则实现位于 scripts/architecture/。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultConfig } from './architecture/config.mjs';
import { inspectProject } from './architecture/project.mjs';

// 兼容原入口 API：测试与外部调用继续从这里 import。
export { defaultConfig, inspectProject };

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = path.dirname(path.dirname(SCRIPT_PATH));

function loadConfig() {
  const configPath = path.join(REPO_ROOT, 'architecture.config.json');
  if (!fs.existsSync(configPath)) {
    console.error(`ARCHITECTURE ERROR: 找不到 ${configPath}`);
    process.exit(2);
  }
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    console.error(`ARCHITECTURE ERROR: 无法解析 architecture.config.json: ${error.message}`);
    process.exit(2);
  }
}

function formatLocation(item) {
  if (!item.file) return '';
  return item.line > 0 ? `${item.file}:${item.line}` : item.file;
}

function main() {
  const config = loadConfig();
  const result = inspectProject(REPO_ROOT, config);

  for (const warning of result.warnings) {
    const where = formatLocation(warning);
    console.warn(`warning ${where ? where + ': ' : ''}${warning.message}`);
  }
  for (const violation of result.violations) {
    const where = formatLocation(violation);
    console.error(`ERROR ${where ? where + ': ' : ''}[${violation.rule}] ${violation.message}`);
  }

  const { stats } = result;
  console.log(
    `Architecture scan: ${stats.productionGdFiles} production scripts, ` +
      `${stats.dependencyEdges} dependency edges, ${stats.scenes} scenes, ` +
      `${stats.contentJsonFiles} content JSON files, ${stats.resourceRefs} resource refs`,
  );
  console.log(
    `Configured exceptions: ${stats.legacyLineBudgets} line budgets, ` +
      `${stats.legacyCrossFeatureEdges} legacy cross-feature edges, ` +
      `${stats.allowedMissingResources} missing-resource allowances`,
  );

  if (result.violations.length > 0) {
    console.error(`ARCHITECTURE FAILED: ${result.violations.length} violation(s)`);
    process.exitCode = 1;
    return;
  }
  console.log('ARCHITECTURE OK');
}

function isDirectInvocation() {
  if (!process.argv[1]) return false;
  const invoked = path.resolve(process.argv[1]);
  const current = path.resolve(SCRIPT_PATH);
  if (process.platform === 'win32') {
    return invoked.toLowerCase() === current.toLowerCase();
  }
  return invoked === current;
}

if (isDirectInvocation()) {
  main();
}
