import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { inspectProject, defaultConfig } from './check-architecture.mjs';

function writeFixture(root, rel, content) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
}

function assertInsideTmpDir(dir) {
  const tmp = fs.realpathSync(os.tmpdir());
  const resolved = fs.realpathSync(dir);
  assert.ok(
    resolved === tmp || resolved.startsWith(tmp + path.sep),
    `临时目录必须位于 os.tmpdir() 内: ${resolved}`,
  );
  return resolved;
}

function makeFixture(t, overrides = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-check-test-'));
  const resolved = assertInsideTmpDir(dir);

  t.after(() => {
    // 删除前再次校验，避免误删临时目录之外的内容。
    const checked = assertInsideTmpDir(resolved);
    fs.rmSync(checked, { recursive: true, force: true });
  });

  writeFixture(
    dir,
    'godot/project.godot',
    'config_version=5\n\n[application]\n\nrun/main_scene="res://app/game.tscn"\n',
  );
  writeFixture(
    dir,
    'godot/app/game.tscn',
    '[gd_scene load_steps=2 format=3]\n\n' +
      '[ext_resource type="Script" path="res://app/game.gd" id="1_game"]\n\n' +
      '[node name="Game" type="Node"]\n' +
      'script = ExtResource("1_game")\n',
  );
  writeFixture(
    dir,
    'godot/app/game.gd',
    'extends Node\nconst BattleView = preload("res://features/battle/view.gd")\n',
  );
  writeFixture(dir, 'godot/core/core_a.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/features/foo/foo.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/features/bar/bar.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/features/battle/view.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/features/title/title_cinematic.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/features/town/town.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/shared/ui/shared_widget.gd', 'extends RefCounted\n');
  writeFixture(dir, 'godot/data/content.json', '{}\n');

  return {
    dir,
    config: { ...defaultConfig(), ...overrides },
  };
}

function assertViolation(result, expectedRule, expectedFile, messagePart) {
  const found = result.violations.find((violation) => (
    violation.rule === expectedRule &&
    violation.file === expectedFile &&
    (messagePart === undefined || violation.message.includes(messagePart))
  ));
  assert.ok(
    found,
    `期望 ${expectedRule} @ ${expectedFile}${messagePart ? ` 包含 "${messagePart}"` : ''}，` +
      `实际: ${JSON.stringify(result.violations)}`,
  );
  return found;
}

test('合法项目通过（app 静态依赖 feature）', (t) => {
  const { dir, config } = makeFixture(t);
  const result = inspectProject(dir, config);
  assert.deepEqual(result.violations, []);
  assert.equal(result.stats.dependencyEdges, 1);
});

test('app/game.gd 引用 features/battle/view.gd 属于合法依赖', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/app/game.gd',
    'extends Node\nconst BattleView = preload("res://features/battle/view.gd")\n',
  );
  const result = inspectProject(dir, config);
  assert.deepEqual(result.violations, []);
  assert.equal(result.stats.dependencyEdges, 1);
});

test('core 反向依赖 feature 被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/core/core_a.gd',
    'extends RefCounted\nconst Foo = preload("res://features/foo/foo.gd")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(result, 'dependency-direction', 'godot/core/core_a.gd', 'feature:foo');
  assertViolation(
    result,
    'dependency-direction',
    'godot/core/core_a.gd',
    'res://features/foo/foo.gd',
  );
});

test('shared 反向依赖 app 被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/shared/ui/shared_widget.gd',
    'extends RefCounted\nconst Game = preload("res://app/game.gd")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(
    result,
    'dependency-direction',
    'godot/shared/ui/shared_widget.gd',
    'shared -> app',
  );
});

test('未许可的跨 feature 依赖被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/features/foo/foo.gd',
    'extends RefCounted\nconst Bar = preload("res://features/bar/bar.gd")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(
    result,
    'dependency-direction',
    'godot/features/foo/foo.gd',
    'feature:bar',
  );
  assertViolation(
    result,
    'dependency-direction',
    'godot/features/foo/foo.gd',
    'res://features/bar/bar.gd',
  );
});

test('显式配置可以许可某条跨 feature 边', (t) => {
  const { dir, config } = makeFixture(t, {
    allowedCrossFeatureEdges: [
      { from: 'title', to: 'town', reason: 'fixture 明确许可跨 feature 边' },
    ],
  });
  writeFixture(
    dir,
    'godot/features/title/title_cinematic.gd',
    'extends RefCounted\nconst Town = preload("res://features/town/town.gd")\n',
  );
  const result = inspectProject(dir, config);
  assert.equal(result.violations.filter((v) => v.rule === 'dependency-direction').length, 0);
  assert.equal(result.violations.length, 0);
});

test('循环依赖被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/core/core_a.gd',
    'extends RefCounted\nconst B = preload("res://core/core_b.gd")\n',
  );
  writeFixture(
    dir,
    'godot/core/core_b.gd',
    'extends RefCounted\nconst A = preload("res://core/core_a.gd")\n',
  );
  const result = inspectProject(dir, config);
  const cycle = assertViolation(
    result,
    'dependency-cycle',
    'godot/core/core_a.gd',
    'godot/core/core_b.gd',
  );
  assert.ok(cycle.message.includes('godot/core/core_a.gd'));
});

test('新文件超过 500 行被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/features/foo/foo.gd',
    'extends RefCounted\n' + '# padding\n'.repeat(500),
  );
  const result = inspectProject(dir, config);
  assertViolation(result, 'line-budget', 'godot/features/foo/foo.gd');
});

test('旧文件超过精确行数预算被拒绝', (t) => {
  const { dir, config } = makeFixture(t, {
    legacyLineBudgets: { 'godot/features/foo/foo.gd': 3 },
  });
  writeFixture(
    dir,
    'godot/features/foo/foo.gd',
    'extends RefCounted\n# a\n# b\n# c\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(result, 'legacy-line-budget', 'godot/features/foo/foo.gd', '4 > 3');
});

test('缺失静态资源被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/app/game.gd',
    'extends Node\nconst Missing = load("res://data/does_not_exist.json")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(
    result,
    'missing-resource',
    'godot/app/game.gd',
    'res://data/does_not_exist.json',
  );
});

test('默认配置不会放行未登记的跨 feature 坏边', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/features/foo/foo.gd',
    'extends RefCounted\nconst Bar = preload("res://features/bar/bar.gd")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(
    result,
    'dependency-direction',
    'godot/features/foo/foo.gd',
    'res://features/bar/bar.gd',
  );
});

test('相对 .gd 导入被拒绝，不能绕开层级图', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/features/foo/foo.gd',
    'extends RefCounted\nconst Bar = preload("../../features/bar/bar.gd")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(
    result,
    'non-res-import',
    'godot/features/foo/foo.gd',
    '../../features/bar/bar.gd',
  );
});

test('注释里的伪依赖被忽略', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/features/foo/foo.gd',
    'extends RefCounted\n# preload("res://features/bar/bar.gd")\n',
  );
  const result = inspectProject(dir, config);
  assert.deepEqual(result.violations, []);
});

test('普通文本提及文件名不会被当作导入', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/shared/ui/shared_widget.gd',
    'extends RefCounted\n' +
      'const Hint := "load ../../features/bar/bar.gd"\n' +
      'const Dynamic = load(some_path)\n',
  );
  const result = inspectProject(dir, config);
  assert.deepEqual(result.violations, []);
});

test('core extends Control 被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(dir, 'godot/core/core_a.gd', 'extends Control\n');
  const result = inspectProject(dir, config);
  assertViolation(result, 'core-scene-type', 'godot/core/core_a.gd', 'Control');
});

test('场景根绑定脚本不在同目录被拒绝', (t) => {
  const { dir, config } = makeFixture(t);
  writeFixture(
    dir,
    'godot/features/foo/rogue.tscn',
    '[gd_scene load_steps=2 format=3]\n\n' +
      '[ext_resource type="Script" path="res://features/bar/bar.gd" id="1_rogue"]\n\n' +
      '[node name="Rogue" type="Node"]\n' +
      'script = ExtResource("1_rogue")\n',
  );
  const result = inspectProject(dir, config);
  assertViolation(
    result,
    'scene-script-adjacency',
    'godot/features/foo/rogue.tscn',
    'res://features/bar/bar.gd',
  );
});
