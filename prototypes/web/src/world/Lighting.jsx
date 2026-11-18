import { useMemo } from 'react'
import { useThree } from '@react-three/fiber'
import { Sparkles } from '@react-three/drei'
import { makeCanvas, toTexture } from '../art/pixel.js'

function makeSkyTexture() {
  const canvas = makeCanvas(4, 256)
  const ctx = canvas.getContext('2d')
  const grad = ctx.createLinearGradient(0, 0, 0, 256)
  grad.addColorStop(0, '#141828')
  grad.addColorStop(0.45, '#2b2b4a')
  grad.addColorStop(0.72, '#63455c')
  grad.addColorStop(1, '#c8845a')
  ctx.fillStyle = grad
  ctx.fillRect(0, 0, 4, 256)
  return toTexture(canvas)
}

export default function Lighting() {
  const { scene } = useThree()

  useMemo(() => {
    scene.background = makeSkyTexture()
    return scene.background
  }, [scene])

  return (
    <>
      <fog attach="fog" args={['#161c2a', 26, 64]} />

      <hemisphereLight args={['#7d8fb3', '#5e4128', 0.6]} />

      <directionalLight
        position={[14, 20, 10]}
        color="#ffd9a0"
        intensity={2.2}
        castShadow
        shadow-mapSize-width={2048}
        shadow-mapSize-height={2048}
        shadow-camera-left={-30}
        shadow-camera-right={30}
        shadow-camera-top={30}
        shadow-camera-bottom={-30}
        shadow-camera-near={1}
        shadow-camera-far={80}
        shadow-bias={-0.0005}
        shadow-normalBias={0.02}
      />

      <Sparkles
        count={60}
        scale={[22, 5, 22]}
        position={[0, 2.4, 0]}
        size={2.6}
        speed={0.25}
        opacity={0.75}
        color="#ffd27a"
        noise={0.6}
      />
    </>
  )
}
