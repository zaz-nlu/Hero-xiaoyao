#!/usr/bin/env node
// Godot 4 质量检查：单元测试、小镇/酒馆/森林场景、默认主场景、游戏冒烟测试。
// 只使用 Node 内置模块。每一步都有独立超时；失败时保留断言、Parse Error、
// SCRIPT ERROR 的上下文，而不是只关心进程退出码。
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const GODOT_DIR = path.join(REPO_ROOT, 'godot');
// 本机默认安装位置；换机器请设置 GODOT_BIN 或把 godot4 / godot 加入 PATH。
const DEFAULT_WINDOWS_ENGINE = 'D:/godot/Godot_v4.7.2-stable_win64_console.exe';

const OUTPUT_ERROR_PATTERNS = [/SCRIPT ERROR/, /Parse Error/, /Failed to load script/];
const CONTEXT_PATTERNS =
  /SCRIPT ERROR|Parse Error|Failed to load script|^\s*FAIL\b|SMOKE FAIL|^\s*at:/;

function isFile(file) {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

function findOnPath(name) {
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);

  if (process.platform === 'win32') {
    const exts = (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM')
      .split(';')
      .filter(Boolean);
    const hasExt = exts.some((ext) => name.toLowerCase().endsWith(ext.toLowerCase()));
    for (const dir of dirs) {
      if (hasExt) {
        const candidate = path.join(dir, name);
        if (isFile(candidate)) return candidate;
        continue;
      }
      for (const ext of exts) {
        const candidate = path.join(dir, name + ext);
        if (isFile(candidate)) return candidate;
      }
    }
    return null;
  }

  for (const dir of dirs) {
    const candidate = path.join(dir, name);
    if (isFile(candidate)) return candidate;
  }
  return null;
}

function resolveCandidate(value) {
  const cleaned = value.replace(/^"(.*)"$/, '$1');
  if (path.isAbsolute(cleaned) || cleaned.includes('/') || cleaned.includes('\\')) {
    return isFile(cleaned) ? cleaned : null;
  }
  return findOnPath(cleaned);
}

function reportEngineNotFound(tried) {
  console.error('无法找到 Godot 4 可执行文件。');
  console.error('请设置 GODOT_BIN 指向 Godot 4.x 的 console 版本，例如：');
  console.error('  PowerShell:  $env:GODOT_BIN = "D:/godot/Godot_v4.7.2-stable_win64_console.exe"');
  console.error('  Git Bash:    export GODOT_BIN="D:/godot/Godot_v4.7.2-stable_win64_console.exe"');
  console.error('或把 godot4 / godot 加入 PATH。已尝试：');
  for (const item of tried) console.error(`  - ${item}`);
  process.exit(2);
}

function resolveEngine() {
  const tried = [];
  const explicit = (process.env.GODOT_BIN || '').trim();

  if (explicit) {
    const resolved = resolveCandidate(explicit);
    if (resolved) return resolved;
    // 明确设置了 GODOT_BIN 却不可用时，不要静默改用其他引擎。
    reportEngineNotFound([`GODOT_BIN=${explicit}（文件不存在或不可执行）`]);
  }
  tried.push('GODOT_BIN（未设置）');

  if (isFile(DEFAULT_WINDOWS_ENGINE)) return DEFAULT_WINDOWS_ENGINE;
  tried.push(DEFAULT_WINDOWS_ENGINE);

  for (const name of ['godot4', 'godot']) {
    const found = findOnPath(name);
    if (found) return found;
    tried.push(`PATH 中的 ${name}`);
  }

  reportEngineNotFound(tried);
}

function quoteArg(arg) {
  return /\s|"/.test(arg) ? `"${arg.replace(/"/g, '\\"')}"` : arg;
}

function formatCommand(step) {
  return [step.command, ...step.args].map(quoteArg).join(' ');
}

function runStep(step) {
  return new Promise((resolve) => {
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    let settled = false;
    let timer = null;
    let child;

    try {
      child = spawn(step.command, step.args, {
        cwd: REPO_ROOT,
        shell: false,
        windowsHide: true,
        detached: process.platform !== 'win32',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (error) {
      resolve({ code: null, signal: null, pid: null, output: '', timedOut: false, error });
      return;
    }

    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ pid: child.pid ?? null, output: stdout + stderr, timedOut, error: null, ...result });
    };

    const killOwnProcessTree = () => {
      timedOut = true;
      if (process.platform === 'win32') {
        // 只按本次 spawn 的 PID 终止该进程树；绝不按进程名结束用户已打开的 Godot。
        const killer = spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], {
          shell: false,
          windowsHide: true,
          stdio: 'ignore',
        });
        killer.on('error', () => {
          try {
            child.kill();
          } catch {
            // 进程可能已经退出。
          }
        });
      } else {
        try {
          process.kill(-child.pid, 'SIGKILL');
        } catch {
          try {
            child.kill('SIGKILL');
          } catch {
            // 进程可能已经退出。
          }
        }
      }
      // taskkill 自己失败时的兜底：最多再等 5 秒后只终止这个 PID。
      setTimeout(() => {
        try {
          child.kill();
        } catch {
          // 进程可能已经退出。
        }
      }, 5000).unref();
    };

    timer = setTimeout(killOwnProcessTree, step.timeoutMs);

    child.stdout?.on('data', (chunk) => {
      stdout += chunk;
    });
    child.stderr?.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('error', (error) => {
      finish({ code: null, signal: null, error });
    });
    child.on('close', (code, signal) => {
      finish({ code, signal, error: null });
    });
  });
}

function hasScriptError(output) {
  return OUTPUT_ERROR_PATTERNS.some((pattern) => pattern.test(output));
}

function contextLines(output, maxLines = 120) {
  const lines = output.split(/\r?\n/);
  const picked = new Set();

  for (let i = 0; i < lines.length; i += 1) {
    if (!CONTEXT_PATTERNS.test(lines[i])) continue;
    const from = Math.max(0, i - 3);
    const to = Math.min(lines.length - 1, i + 3);
    for (let j = from; j <= to; j += 1) picked.add(j);
  }

  let selected;
  if (picked.size === 0) {
    selected = lines.slice(-60);
  } else {
    selected = [...picked].sort((a, b) => a - b).map((index) => lines[index]);
  }

  if (selected.length > maxLines) {
    const omitted = selected.length - maxLines;
    selected = selected.slice(-maxLines);
    selected.unshift(`...（前面还有 ${omitted} 行相关输出未显示）`);
  }
  return selected.join('\n').trim();
}

function commonProblems(step, result) {
  const problems = [];
  if (result.error) {
    problems.push(`无法启动引擎：${result.error.message}`);
  }
  if (result.timedOut) {
    problems.push(`超时（${step.timeoutMs} ms），已终止本次 spawn 的进程树`);
  }
  if (!result.error && !result.timedOut && result.code !== 0) {
    problems.push(`退出码 ${result.code}${result.signal ? `，signal ${result.signal}` : ''}`);
  }
  if (hasScriptError(result.output)) {
    problems.push('输出包含 SCRIPT ERROR / Parse Error');
  }
  return problems;
}

function validateTests(step, result) {
  const problems = commonProblems(step, result);
  const summary = result.output.match(/^PASS (\d+) \/ FAIL (\d+)\s*$/m);

  if (!summary) {
    problems.push('没有找到 "PASS n / FAIL n" 汇总行（可能没有发现任何测试）');
    return { problems, summaryText: '无测试汇总' };
  }

  const passed = Number(summary[1]);
  const failed = Number(summary[2]);
  if (passed === 0) problems.push('没有发现任何测试（PASS 0）');
  if (failed > 0) problems.push(`测试失败 ${failed} 个`);
  return { problems, summaryText: `PASS ${passed} / FAIL ${failed}` };
}

function validateScene(step, result) {
  return { problems: commonProblems(step, result), summaryText: '' };
}

function validateSmoke(step, result) {
  const problems = commonProblems(step, result);
  if (!/SMOKE OK/.test(result.output)) {
    problems.push('没有输出 SMOKE OK');
  }
  if (/SMOKE FAIL/.test(result.output)) {
    problems.push('冒烟测试报告 SMOKE FAIL');
  }
  return { problems, summaryText: 'SMOKE OK' };
}

const ENGINE = resolveEngine();

const steps = [
  {
    name: '单元测试',
    args: ['--headless', '--path', GODOT_DIR, '-s', 'res://tests/run_tests.gd'],
    timeoutMs: 280000,
    validate: validateTests,
  },
  {
    name: '小镇场景',
    args: ['--headless', '--path', GODOT_DIR, 'res://features/town/town.tscn', '--quit-after', '5'],
    timeoutMs: 120000,
    validate: validateScene,
  },
  {
    name: '酒馆场景',
    args: ['--headless', '--path', GODOT_DIR, 'res://features/tavern/tavern.tscn', '--quit-after', '5'],
    timeoutMs: 120000,
    validate: validateScene,
  },
  {
    name: '森林场景',
    args: ['--headless', '--path', GODOT_DIR, 'res://features/forest/forest.tscn', '--quit-after', '5'],
    timeoutMs: 120000,
    validate: validateScene,
  },
  {
    name: '默认主场景',
    args: ['--headless', '--path', GODOT_DIR, '--quit-after', '5'],
    timeoutMs: 120000,
    validate: validateScene,
  },
  {
    name: '游戏冒烟测试',
    args: ['--headless', '--path', GODOT_DIR, '-s', 'res://tools/smoke_game.gd'],
    timeoutMs: 180000,
    validate: validateSmoke,
  },
];

function printFailure(step, result, problems) {
  console.log('');
  console.log(`命令: ${formatCommand({ ...step, command: ENGINE })}`);
  if (result.pid) console.log(`进程 PID: ${result.pid}`);
  for (const problem of problems) console.log(`原因: ${problem}`);
  console.log('--- 相关输出 ---');
  const context = contextLines(result.output);
  console.log(context === '' ? '（无输出）' : context);
  console.log('----------------');
}

async function main() {
  for (let i = 0; i < steps.length; i += 1) {
    const step = steps[i];
    process.stdout.write(`[${i + 1}/${steps.length}] ${step.name} ... `);
    const result = await runStep({ ...step, command: ENGINE });
    const verdict = step.validate(step, result);

    if (verdict.problems.length > 0) {
      console.log('FAILED');
      printFailure(step, result, verdict.problems);
      console.log(`CHECK FAILED: ${step.name}`);
      process.exitCode = 1;
      return;
    }

    console.log(`OK${verdict.summaryText ? ` (${verdict.summaryText})` : ''}`);
  }

  console.log(`CHECK OK (${steps.length}/${steps.length} steps passed)`);
}

await main();
