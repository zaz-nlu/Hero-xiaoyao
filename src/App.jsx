import React from 'react'
import { Canvas } from '@react-three/fiber'
import Scene from './Scene.jsx'
import Effects from './Effects.jsx'

const hintStyle = {
  position: 'absolute',
  top: 16,
  left: 16,
  padding: '8px 12px',
  background: 'rgba(10, 12, 18, 0.55)',
  border: '1px solid rgba(255, 255, 255, 0.15)',
  borderRadius: 2,
  color: '#e8e0cc',
  fontFamily: "'Courier New', monospace",
  fontSize: 13,
  letterSpacing: 1,
  imageRendering: 'pixelated',
  pointerEvents: 'none',
  userSelect: 'none',
}

export default function App() {
  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'linear-gradient(#141828, #2b2b4a 45%, #63455c 72%, #c8845a)',
      }}
    >
      <Canvas shadows dpr={[1, 2]} flat gl={{ antialias: false }}>
        <Scene />
        <Effects />
      </Canvas>
      <div style={hintStyle}>WASD 移动 · Shift 跑 · Q/E 旋转视角</div>
    </div>
  )
}
