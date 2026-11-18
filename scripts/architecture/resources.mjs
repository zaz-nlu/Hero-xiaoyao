import fs from 'node:fs';
import path from 'node:path';
import { relFrom, walkFiles } from './fsutil.mjs';
import { extractResPaths, scanStringLiterals } from './lexer.mjs';

function parseProjectMainScene(root, godotRoot, config, addViolation) {
  const projectAbs = path.join(godotRoot, config.projectFile);
  const projectRel = relFrom(root, projectAbs);
  if (!fs.existsSync(projectAbs)) {
    addViolation('missing-project-file', projectRel, 0, 'project.godot 不存在');
    return null;
  }

  const lines = fs.readFileSync(projectAbs, 'utf8').split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const match = lines[i].match(/^\s*run\/main_scene\s*=\s*"([^"]+)"/);
    if (!match) continue;
    if (!match[1].startsWith('res://')) {
      addViolation(
        'missing-main-scene',
        projectRel,
        i + 1,
        `main_scene 不是 res:// 路径: ${match[1]}`,
      );
      return null;
    }
    return { file: projectRel, line: i + 1, path: match[1] };
  }

  addViolation('missing-main-scene', projectRel, 0, 'project.godot 未设置 run/main_scene');
  return null;
}

function collectGdRefs(files) {
  const refs = [];
  for (const file of files) {
    for (const literal of scanStringLiterals(file.content)) {
      for (const resPath of extractResPaths(literal.value)) {
        refs.push({ file: file.rel, line: literal.line, path: resPath });
      }
    }
  }
  return refs;
}

function collectContentRefs(root, godotRoot, config) {
  const files = [];
  for (const dirName of config.contentDirs) {
    const base = path.join(godotRoot, dirName);
    files.push(...walkFiles(base, (name) => name.endsWith('.json')));
  }
  files.sort();

  const refs = [];
  for (const abs of files) {
    const rel = relFrom(root, abs);
    const lines = fs.readFileSync(abs, 'utf8').split(/\r?\n/);
    for (let i = 0; i < lines.length; i += 1) {
      for (const resPath of extractResPaths(lines[i])) {
        refs.push({ file: rel, line: i + 1, path: resPath });
      }
    }
  }
  return { count: files.length, refs };
}

function collectSceneRefs(root, godotRoot, addViolation) {
  const scenes = walkFiles(godotRoot, (name) => name.endsWith('.tscn'));
  const refs = [];

  for (const abs of scenes) {
    const rel = relFrom(root, abs);
    const lines = fs.readFileSync(abs, 'utf8').split(/\r?\n/);
    const extResources = new Map();
    let rootNodeIndex = -1;

    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      if (/^\[ext_resource\b/.test(line)) {
        const pathMatch = line.match(/\bpath="([^"]+)"/);
        const idMatch = line.match(/\bid="([^"]+)"/);
        if (pathMatch && idMatch) {
          extResources.set(idMatch[1], { path: pathMatch[1], line: i + 1 });
        }
        if (pathMatch && pathMatch[1].startsWith('res://')) {
          refs.push({ file: rel, line: i + 1, path: pathMatch[1] });
        }
      } else if (rootNodeIndex < 0 && /^\[node\b/.test(line) && !/\bparent=/.test(line)) {
        rootNodeIndex = i;
      }
    }

    if (rootNodeIndex < 0) continue;

    let scriptId = null;
    let scriptLine = 0;
    for (let i = rootNodeIndex + 1; i < lines.length; i += 1) {
      if (lines[i].startsWith('[')) break;
      const match = lines[i].match(/^\s*script\s*=\s*ExtResource\("([^"]+)"\)/);
      if (match) {
        scriptId = match[1];
        scriptLine = i + 1;
        break;
      }
    }
    if (!scriptId) continue;

    const resource = extResources.get(scriptId);
    if (!resource) {
      addViolation(
        'broken-scene-script',
        rel,
        scriptLine,
        `根节点脚本 ExtResource("${scriptId}") 没有对应的 ext_resource 声明`,
      );
      continue;
    }
    if (!resource.path.startsWith('res://')) continue;

    const scriptGodotRel = resource.path.slice('res://'.length);
    const sceneGodotRel = relFrom(godotRoot, abs);
    if (path.posix.dirname(scriptGodotRel) !== path.posix.dirname(sceneGodotRel)) {
      addViolation(
        'scene-script-adjacency',
        rel,
        scriptLine,
        `根节点脚本 ${resource.path} 必须与场景同目录`,
      );
    }
  }

  return { count: scenes.length, refs };
}

function checkDirectories(root, godotRoot, config, addViolation) {
  for (const oldRoot of config.oldRoots) {
    const oldDir = path.join(godotRoot, oldRoot.slice('res://'.length));
    if (!fs.existsSync(oldDir)) continue;
    const leftovers = walkFiles(
      oldDir,
      (name) => name.endsWith('.gd') || name.endsWith('.tscn'),
    );
    if (leftovers.length > 0) {
      addViolation(
        'old-root-directory',
        relFrom(root, leftovers[0]),
        1,
        `${oldRoot} 是已废弃目录，不能继续存放脚本或场景`,
      );
    }
  }

  if (!fs.existsSync(godotRoot)) return;

  const allowedTopDirs = new Set([
    ...config.productionDirs,
    'tests',
    'tools',
    'data',
    'assets',
  ]);
  const legacyTopDirs = new Set(
    config.oldRoots.map((prefix) => prefix.slice('res://'.length).replace(/\/$/, '')),
  );

  for (const entry of fs.readdirSync(godotRoot, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.endsWith('.gd')) {
      addViolation(
        'stray-gd',
        `${config.godotDir}/${entry.name}`,
        1,
        '生产脚本必须放在 app/core/features/shared 之一',
      );
      continue;
    }
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    if (allowedTopDirs.has(entry.name) || legacyTopDirs.has(entry.name)) continue;

    const stray = walkFiles(path.join(godotRoot, entry.name), (name) => name.endsWith('.gd'));
    if (stray.length > 0) {
      addViolation(
        'stray-gd',
        relFrom(root, stray[0]),
        1,
        `生产脚本必须放在 app/core/features/shared 之一（发现于 ${entry.name}/）`,
      );
    }
  }
}

function checkExistence(root, godotRoot, refs, config, addViolation, warnings) {
  const allowedMissing = new Map(
    config.allowedMissingResources.map((entry) => [entry.path, entry]),
  );
  const seenAllowedMissing = new Set();

  for (const ref of refs) {
    if (!ref.path.startsWith('res://')) continue;

    if (config.oldRoots.some((prefix) => ref.path.startsWith(prefix))) {
      addViolation('old-root-reference', ref.file, ref.line, `禁止引用旧路径 ${ref.path}`);
    }

    const targetAbs = path.join(godotRoot, ref.path.slice('res://'.length));
    if (fs.existsSync(targetAbs)) {
      if (allowedMissing.has(ref.path)) {
        addViolation(
          'stale-missing-allowance',
          ref.file,
          ref.line,
          `资源已存在，allowedMissingResources 中的例外应删除: ${ref.path}`,
        );
      }
      continue;
    }

    if (allowedMissing.has(ref.path)) {
      if (!seenAllowedMissing.has(ref.path)) {
        seenAllowedMissing.add(ref.path);
        warnings.push({
          file: ref.file,
          line: ref.line,
          message: `allowed missing resource ${ref.path}: ${allowedMissing.get(ref.path).reason}`,
        });
      }
      continue;
    }

    addViolation('missing-resource', ref.file, ref.line, `静态资源不存在: ${ref.path}`);
  }

  for (const resPath of allowedMissing.keys()) {
    if (seenAllowedMissing.has(resPath)) continue;
    addViolation(
      'unused-missing-allowance',
      'architecture.config.json',
      0,
      `allowedMissingResources 未匹配到实际引用，请删除: ${resPath}`,
    );
  }
}

export function validateProjectAndResources({
  root,
  godotRoot,
  config,
  files,
  addViolation,
  warnings,
}) {
  const mainSceneRef = parseProjectMainScene(root, godotRoot, config, addViolation);
  const content = collectContentRefs(root, godotRoot, config);
  const scenes = collectSceneRefs(root, godotRoot, addViolation);

  const refs = [
    ...(mainSceneRef ? [mainSceneRef] : []),
    ...collectGdRefs(files),
    ...content.refs,
    ...scenes.refs,
  ];

  checkExistence(root, godotRoot, refs, config, addViolation, warnings);
  checkDirectories(root, godotRoot, config, addViolation);

  return {
    scenes: scenes.count,
    contentJsonFiles: content.count,
    resourceRefs: refs.length,
  };
}
