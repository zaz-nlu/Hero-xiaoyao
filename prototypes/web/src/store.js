import { useSyncExternalStore } from 'react'

// 轻量全局 store：模块级可变状态 + 订阅，不引入额外依赖
let state = {
  playerPos: { x: 0, z: 0 },
}

const listeners = new Set()

export function getState() {
  return state
}

export function setPlayerPos(x, z) {
  const p = state.playerPos
  if (p.x === x && p.z === z) return
  state = { ...state, playerPos: { x, z } }
  listeners.forEach((fn) => fn())
}

export function subscribe(fn) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

export function usePlayerPos() {
  return useSyncExternalStore(subscribe, () => state.playerPos, () => state.playerPos)
}
