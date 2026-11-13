import * as THREE from 'three'

// ---------------------------------------------------------------------------
// 基础工具：所有像素画都用 canvas 逐像素生成，零外部素材
// ---------------------------------------------------------------------------

export function makeCanvas(w, h) {
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  ctx.imageSmoothingEnabled = false
  return canvas
}

// rows: 字符矩阵（字符串数组），palette: 字符 -> 颜色；'.' 与空格为透明
export function paint(ctx, rows, palette, ox = 0, oy = 0) {
  for (let y = 0; y < rows.length; y++) {
    const row = rows[y]
    for (let x = 0; x < row.length; x++) {
      const ch = row[x]
      if (ch === '.' || ch === ' ') continue
      const color = palette[ch]
      if (!color) continue
      ctx.fillStyle = color
      ctx.fillRect(ox + x, oy + y, 1, 1)
    }
  }
}

export function toTexture(canvas, repeat = false) {
  const tex = new THREE.CanvasTexture(canvas)
  tex.magFilter = THREE.NearestFilter
  tex.minFilter = THREE.NearestFilter
  tex.generateMipmaps = false
  tex.colorSpace = THREE.SRGBColorSpace
  if (repeat) {
    tex.wrapS = THREE.RepeatWrapping
    tex.wrapT = THREE.RepeatWrapping
  }
  tex.needsUpdate = true
  return tex
}

function hash2(x, y) {
  const n = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return n - Math.floor(n)
}

// ---------------------------------------------------------------------------
// 游侠精灵表：24x32 / 帧，4 帧 x 4 方向（下、上、左、右），右手方向镜像左手
// ---------------------------------------------------------------------------

const RANGER_PALETTE = {
  o: '#1a1410', // 描边
  h: '#2f5d3a', // 兜帽暗部
  H: '#4a8a58', // 兜帽亮部
  c: '#28502f', // 斗篷边缘
  C: '#356b42', // 斗篷主体
  k: '#1e3d26', // 斗篷阴影
  b: '#5c3a1f', // 皮革暗部
  B: '#7d5029', // 皮革主体
  l: '#a06a38', // 皮革亮部
  m: '#cbb96a', // 腰带扣
  s: '#e9b58c', // 皮肤
  e: '#2a1710', // 眼睛
  w: '#6f451f', // 弓身
  f: '#d8d2b8', // 箭羽
  t: '#35251a', // 靴子
}

const FRAME_W = 24
const FRAME_H = 32

// 正面（朝下）身体，第 0-18 行
const BODY_DOWN = [
  '........................',
  '........................',
  '.......oooooooooo.......',
  '......ohhhhhhhhhho......',
  '......ohHHHHHHHHho......',
  '......ohssssssssho......',
  '......ohsessssesho......',
  '......ohssssssssho......',
  '.......ohssssssho.......',
  '.......ohhhhhhhho.......',
  '.....ocCCCCCCCCCCco.....',
  '.....ocBbBBBBBBbCco.....',
  '.....ocBbBBmmBBbCco.....',
  '.....ocCbbbbbbbbCco.....',
  '.....ocCCCCCCCCCCco.....',
  '....socCCCCCCCCCCcos....',
  '....sokCCCCCCCCCCkos....',
  '.....okCCCCCCCCCCko.....',
  '.....okCCkCCCCkCCko.....',
]

// 背面（朝上）身体：兜帽背面、后背的弓与箭袋
const BODY_UP = [
  '........................',
  '........................',
  '.......oooooooooo.......',
  '......ohhhhhhhhhho......',
  '......ohHHhhhhHHho......',
  '......ohHHhhhhHHho......',
  '......ohhhhhhhhhho......',
  '......ohhhhhhhhhho......',
  '.......ohhffffhho.......',
  '.......ohhbbbbhho.......',
  '.....ocCCCCCCbbbbco.....',
  '.....ocCwCCCCbbbbco.....',
  '.....ocCwCCCCbbbbco.....',
  '.....ocwCCCCCbbbbco.....',
  '.....ocwCCCCCbbbbco.....',
  '.....ocwCCCCCbbbbco.....',
  '....socwCCCCCbbbbcos....',
  '.....ocCwCCCCbbbbco.....',
  '.....okCwCCkCbbbbko.....',
]

// 侧面（朝左）身体：脸部朝左，背后的弓在右缘
const BODY_SIDE = [
  '........................',
  '........................',
  '.......oooooooo.........',
  '......ohhhhhhhho........',
  '.....ohhHHHHHHho........',
  '.....ohhsessssho........',
  '....ohhsesssshho........',
  '.....ohhssssshho........',
  '......ohhhhhhhho........',
  '......ohhffffhho........',
  '....ocCCCCCCCCcow.......',
  '....obBBBCCCCCCow.......',
  '....obBBBCCCCCC.w.......',
  '....obbbbCCCCCC..w......',
  '....ocCCCCCCCCco.w......',
  '....ocCCCCCCCCco.w......',
  '....ocCCCCCCCCco.w......',
  '....okCCCCCCCCko........',
  '....okCCCCCCCCko........',
]

// 正面/背面共用的腿部帧（第 19-31 行）
const FRONT_FRAMES = [
  // f0 站立
  [
    '.....okCCCCCCCCCCko.....',
    '.....okkCCCCCCCCkko.....',
    '.....oooooooooooooo.....',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........otto.otto.......',
    '........otto.otto.......',
    '.......ottto.ottto......',
    '.......ottto.ottto......',
  ],
  // f1 左腿前迈
  [
    '.....okCCCCCCCCCCko.....',
    '.....okkCCCCCCCCkko.....',
    '....ooooooooooooooo.....',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......otto..obbo.......',
    '.......otto..otto.......',
    '......ottto..otto.......',
    '......ottto..ottto......',
    '......ottto.............',
  ],
  // f2 过渡帧
  [
    '.....okCCCCCCCCCCko.....',
    '.....okkCCCCCCCCkko.....',
    '.....ooooooooooooooo....',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '........obbo.obbo.......',
    '.......obbo..obbo.......',
    '.......otto..otto.......',
    '........otto.otto.......',
    '........otto.otto.......',
    '.......ottto.ottto......',
  ],
  // f3 右腿前迈
  [
    '.....okCCCCCCCCCCko.....',
    '.....okkCCCCCCCCkko.....',
    '.....ooooooooooooooo....',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..obbo.......',
    '.......obbo..otto.......',
    '.......otto..otto.......',
    '.......otto..ottto......',
    '......ottto..ottto......',
    '.............ottto......',
  ],
]

// 侧面腿部帧（第 19-31 行）
const SIDE_FRAMES = [
  // f0 站立
  [
    '....okCCCCCCCCko........',
    '....okkCCCCCCkko........',
    '....oooooooooooo........',
    '........obbo............',
    '........obbo............',
    '........obbo............',
    '........obbo............',
    '........obbo............',
    '........obbo............',
    '........otto............',
    '.......otttto...........',
    '.......otttto...........',
    '......ottttto...........',
  ],
  // f1
  [
    '....okCCCCCCCCko........',
    '....okkCCCCCCkko........',
    '...ooooooooooooo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......otto.obbo........',
    '.......otto.otto........',
    '......ottto.otto........',
    '......ottto.ottto.......',
    '......ottto.............',
  ],
  // f2
  [
    '....okCCCCCCCCko........',
    '....okkCCCCCCkko........',
    '....ooooooooooooo.......',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.otto........',
    '.......otto.otto........',
    '........otto.otto.......',
    '........otto.otto.......',
    '.......ottto.ottto......',
  ],
  // f3
  [
    '....okCCCCCCCCko........',
    '....okkCCCCCCkko........',
    '.....ooooooooooooo......',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.obbo........',
    '.......obbo.otto........',
    '.......otto.otto........',
    '.......otto.ottto.......',
    '......ottto.ottto.......',
    '.............ottto......',
  ],
]

function normRow(row, width) {
  if (row.length === width) return row
  if (row.length < width) return row + '.'.repeat(width - row.length)
  return row.slice(0, width)
}

function mirrorRow(row) {
  return row.split('').reverse().join('')
}

const RANGER_ROWS = { down: 0, up: 1, left: 2, right: 3 }

let _rangerSheet = null

export function getRangerFrames() {
  if (_rangerSheet) return _rangerSheet

  const cols = 4
  const rows = 4
  const canvas = makeCanvas(FRAME_W * cols, FRAME_H * rows)
  const ctx = canvas.getContext('2d')

  const dirs = [
    { body: BODY_DOWN, frames: FRONT_FRAMES, mirror: false },
    { body: BODY_UP, frames: FRONT_FRAMES, mirror: false },
    { body: BODY_SIDE, frames: SIDE_FRAMES, mirror: false },
    { body: BODY_SIDE, frames: SIDE_FRAMES, mirror: true },
  ]

  dirs.forEach((dir, row) => {
    dir.frames.forEach((frame, col) => {
      let frameRows = [...dir.body, ...frame].map((r) => normRow(r, FRAME_W))
      if (dir.mirror) frameRows = frameRows.map(mirrorRow)
      paint(ctx, frameRows, RANGER_PALETTE, col * FRAME_W, row * FRAME_H)
    })
  })

  _rangerSheet = {
    texture: toTexture(canvas),
    cols,
    rows,
    frames: {
      down: [0, 1, 2, 3],
      up: [0, 1, 2, 3],
      left: [0, 1, 2, 3],
      right: [0, 1, 2, 3],
    },
    rowOf: { ...RANGER_ROWS },
  }
  return _rangerSheet
}

// ---------------------------------------------------------------------------
// 树木（32x48）
// ---------------------------------------------------------------------------

let _treeTexture = null

export function getTreeTexture() {
  if (_treeTexture) return _treeTexture

  const W = 32
  const H = 48
  const canvas = makeCanvas(W, H)
  const ctx = canvas.getContext('2d')

  // 树干与根部
  for (let y = 24; y < 47; y++) {
    for (let x = 13; x <= 18; x++) {
      const edge = x === 13 || x === 18
      let color = edge ? '#241a12' : x < 16 ? '#5c3c22' : '#6f4a2a'
      if (!edge && hash2(x, y) > 0.82) color = '#4b3019'
      ctx.fillStyle = color
      ctx.fillRect(x, y, 1, 1)
    }
  }
  for (let x = 11; x <= 20; x++) {
    ctx.fillStyle = '#3a2818'
    ctx.fillRect(x, 45, 1, 1)
    ctx.fillStyle = '#241a12'
    ctx.fillRect(x, 46, 1, 1)
  }

  // 三层松树冠，由下往上叠，形成层次
  const tiers = [
    { top: 20, bottom: 36, half: 14 },
    { top: 11, bottom: 28, half: 11 },
    { top: 3, bottom: 20, half: 8 },
  ]
  for (const tier of tiers) {
    for (let y = tier.top; y <= tier.bottom; y++) {
      const k = (y - tier.top) / (tier.bottom - tier.top)
      const hw = Math.round(1 + k * (tier.half - 1))
      for (let x = 16 - hw; x < 16 + hw; x++) {
        const edge = x === 16 - hw || x === 16 + hw - 1
        let color
        if (edge) {
          color = '#1c3322'
        } else {
          const n = hash2(x, y)
          if (n < 0.2) color = '#24472c'
          else if (n < 0.55) color = '#2f6038'
          else if (n < 0.85) color = '#3d7a46'
          else color = '#529553'
        }
        ctx.fillStyle = color
        ctx.fillRect(x, y, 1, 1)
      }
    }
    // 每层底边的锯齿
    for (let x = 16 - tier.half + 1; x < 16 + tier.half - 1; x += 2) {
      ctx.fillStyle = '#1c3322'
      ctx.fillRect(x, tier.bottom + 1, 1, 1)
    }
  }

  _treeTexture = toTexture(canvas)
  return _treeTexture
}

// ---------------------------------------------------------------------------
// 草地（16x16，平铺）
// ---------------------------------------------------------------------------

let _grassTexture = null

export function getGrassTexture() {
  if (_grassTexture) return _grassTexture

  const canvas = makeCanvas(16, 16)
  const ctx = canvas.getContext('2d')

  for (let y = 0; y < 16; y++) {
    for (let x = 0; x < 16; x++) {
      const n = hash2(x, y)
      let color
      if (n < 0.22) color = '#3c6a34'
      else if (n < 0.52) color = '#4a7c3c'
      else if (n < 0.8) color = '#57903f'
      else if (n < 0.96) color = '#638f46'
      else color = '#2e5429'
      ctx.fillStyle = color
      ctx.fillRect(x, y, 1, 1)
    }
  }

  // 草丛
  const tufts = [
    [2, 3], [7, 1], [11, 6], [4, 10], [13, 12], [9, 14], [0, 13], [15, 4],
  ]
  for (const [x, y] of tufts) {
    ctx.fillStyle = '#2c4f28'
    ctx.fillRect(x, y, 1, 1)
    ctx.fillStyle = '#6fa04b'
    ctx.fillRect((x + 1) % 16, y, 1, 1)
  }

  // 零星小花
  const flowers = [
    [3, 5, '#e8e2c0'],
    [12, 3, '#e6b6cf'],
    [6, 12, '#f0d86a'],
  ]
  for (const [x, y, color] of flowers) {
    ctx.fillStyle = color
    ctx.fillRect(x, y, 1, 1)
  }

  _grassTexture = toTexture(canvas, true)
  return _grassTexture
}

// ---------------------------------------------------------------------------
// 岩石（16x16，平铺）
// ---------------------------------------------------------------------------

let _rockTexture = null

export function getRockTexture() {
  if (_rockTexture) return _rockTexture

  const canvas = makeCanvas(16, 16)
  const ctx = canvas.getContext('2d')

  for (let y = 0; y < 16; y++) {
    for (let x = 0; x < 16; x++) {
      const n = hash2(x, y)
      let color
      if (n < 0.25) color = '#6f6b62'
      else if (n < 0.55) color = '#807b70'
      else if (n < 0.82) color = '#918b7e'
      else color = '#a19a8a'
      ctx.fillStyle = color
      ctx.fillRect(x, y, 1, 1)
    }
  }

  // 裂纹
  const cracks = [
    [3, 2], [4, 3], [4, 4], [5, 5], [6, 6], [7, 6],
    [10, 9], [11, 10], [11, 11], [12, 12], [12, 13],
  ]
  for (const [x, y] of cracks) {
    ctx.fillStyle = '#4c4a44'
    ctx.fillRect(x, y, 1, 1)
  }

  // 苔藓
  const moss = [[1, 1], [2, 1], [1, 2], [8, 2], [9, 3], [2, 9], [3, 9]]
  for (const [x, y] of moss) {
    ctx.fillStyle = '#4d6b3c'
    ctx.fillRect(x, y, 1, 1)
  }

  _rockTexture = toTexture(canvas, true)
  return _rockTexture
}

// ---------------------------------------------------------------------------
// 小花（8x8）
// ---------------------------------------------------------------------------

const FLOWER_PALETTE = {
  p: '#e8c8e0',
  y: '#f2cf5a',
  g: '#3f7a3f',
  G: '#2c5a2e',
}

const FLOWER_ROWS = [
  '........',
  '...pp...',
  '..pyyp..',
  '...pp...',
  '...gg...',
  '..ggG...',
  '...gg...',
  '...GG...',
]

let _flowerTexture = null

export function getFlowerTexture() {
  if (_flowerTexture) return _flowerTexture

  const canvas = makeCanvas(8, 8)
  const ctx = canvas.getContext('2d')
  paint(ctx, FLOWER_ROWS, FLOWER_PALETTE)
  _flowerTexture = toTexture(canvas)
  return _flowerTexture
}
