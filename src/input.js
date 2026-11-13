// 模块级键盘状态，不依赖任何框架
export const keys = new Set()

const TRACKED = new Set([
  'KeyW', 'KeyA', 'KeyS', 'KeyD',
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'ShiftLeft', 'ShiftRight',
  'KeyQ', 'KeyE',
])

if (typeof window !== 'undefined') {
  window.addEventListener('keydown', (e) => {
    if (!TRACKED.has(e.code)) return
    keys.add(e.code)
    if (e.code.startsWith('Arrow')) e.preventDefault()
  })
  window.addEventListener('keyup', (e) => {
    if (!TRACKED.has(e.code)) return
    keys.delete(e.code)
  })
  window.addEventListener('blur', () => keys.clear())
}

// W = -z, S = +z, A = -x, D = +x
export function getMoveVector() {
  let x = 0
  let z = 0
  if (keys.has('KeyW') || keys.has('ArrowUp')) z -= 1
  if (keys.has('KeyS') || keys.has('ArrowDown')) z += 1
  if (keys.has('KeyA') || keys.has('ArrowLeft')) x -= 1
  if (keys.has('KeyD') || keys.has('ArrowRight')) x += 1
  return { x, z }
}

export function isRunning() {
  return keys.has('ShiftLeft') || keys.has('ShiftRight')
}
