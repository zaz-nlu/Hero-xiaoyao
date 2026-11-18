// 架构策略与配置校验。项目级例外全部来自 architecture.config.json。
const CORE_FORBIDDEN_BASE_CLASSES = [
  'Node', 'Node2D', 'Node3D', 'Control', 'CanvasItem', 'CanvasLayer',
  'Viewport', 'SubViewport', 'Window',
  'Sprite2D', 'Sprite3D', 'AnimatedSprite2D', 'AnimatedSprite3D',
  'MeshInstance3D', 'MultiMeshInstance3D', 'QuadMesh',
  'Camera2D', 'Camera3D',
  'CharacterBody2D', 'CharacterBody3D', 'StaticBody2D', 'StaticBody3D',
  'RigidBody2D', 'RigidBody3D', 'Area2D', 'Area3D',
  'CollisionShape2D', 'CollisionShape3D',
  'Label', 'Label3D', 'Button', 'CheckBox', 'OptionButton',
  'Panel', 'PanelContainer', 'VBoxContainer', 'HBoxContainer',
  'GridContainer', 'MarginContainer', 'CenterContainer', 'ScrollContainer',
  'TextureRect', 'ColorRect', 'RichTextLabel', 'LineEdit', 'TextEdit',
  'ProgressBar', 'Timer', 'AnimationPlayer', 'AnimationTree',
  'AudioStreamPlayer', 'AudioStreamPlayer3D', 'AudioStreamPlayer2D',
  'WorldEnvironment', 'DirectionalLight3D', 'OmniLight3D', 'SpotLight3D',
  'GPUParticles3D', 'CPUParticles3D',
];

export function defaultConfig() {
  return {
    godotDir: 'godot',
    projectFile: 'project.godot',
    productionDirs: ['app', 'core', 'features', 'shared'],
    contentDirs: ['data'],
    oldRoots: ['res://world/', 'res://ui/'],
    defaultMaxLines: 500,
    legacyLineBudgets: {},
    allowedCrossFeatureEdges: [],
    // 存量坏边只能按“精确文件 + 精确行号”登记，不按目录或 feature 放宽。
    legacyCrossFeatureEdges: [],
    // 仅允许精确资源路径，且必须给出原因。
    allowedMissingResources: [],
    coreForbiddenBaseClasses: [...CORE_FORBIDDEN_BASE_CLASSES],
  };
}

export function validateConfig(config, addViolation) {
  for (const entry of config.allowedCrossFeatureEdges) {
    if (!entry.reason) {
      addViolation(
        'config-reason-required',
        'architecture.config.json',
        0,
        `跨 feature 许可 ${entry.from} -> ${entry.to} 缺少 reason`,
      );
    }
  }
  for (const entry of config.legacyCrossFeatureEdges) {
    if (!entry.reason) {
      addViolation(
        'config-reason-required',
        'architecture.config.json',
        0,
        `legacy 跨 feature 边 ${entry.fromPath}:${entry.line} 缺少 reason`,
      );
    }
  }
  for (const entry of config.allowedMissingResources) {
    if (!entry.reason) {
      addViolation(
        'config-reason-required',
        'architecture.config.json',
        0,
        `资源缺失许可 ${entry.path} 缺少 reason`,
      );
    }
  }
}
