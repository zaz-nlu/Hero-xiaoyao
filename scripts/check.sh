#!/bin/bash
# 兼容入口：完整质量入口是 `npm run check`。
# 这里只按顺序调用两个 Node 检查脚本；引擎发现、超时和失败上下文都在
# scripts/check-godot.mjs 中，任一检查失败即以非 0 退出。
cd "$(dirname "$0")/.." || exit 9
set -e
node scripts/check-architecture.mjs
node scripts/check-godot.mjs
