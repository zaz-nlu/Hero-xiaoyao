import { useMemo, useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'
import { getGrassTexture } from '../art/pixel.js'

export const POND = { x: -6, z: 5, r: 3.4, collide: 2.5 }

// 低频起伏（幅度 <= 0.6），中心 12x12 压平，池塘下陷
export function heightAt(x, z) {
  const base =
    0.34 * Math.sin(x * 0.33 + 0.7) * Math.cos(z * 0.29) +
    0.2 * Math.sin(x * 0.16 - z * 0.21 + 1.2)

  const ox = Math.max(Math.abs(x) - 6, 0)
  const oz = Math.max(Math.abs(z) - 6, 0)
  const t = Math.min(Math.hypot(ox, oz) / 5, 1)
  const smooth = t * t * (3 - 2 * t)
  let h = base * smooth

  const pd = Math.hypot(x - POND.x, z - POND.z)
  if (pd < POND.r + 1.4) {
    const k = 1 - pd / (POND.r + 1.4)
    h -= k * k * 1.9
  }
  return h
}

const SIDE_WALLS = [
  { p: [0, -1, -19.8], s: [40.8, 2, 0.8] },
  { p: [0, -1, 19.8], s: [40.8, 2, 0.8] },
  { p: [-19.8, -1, 0], s: [0.8, 2, 40.8] },
  { p: [19.8, -1, 0], s: [0.8, 2, 40.8] },
]

export default function Terrain() {
  const waterRef = useRef()

  const geometry = useMemo(() => {
    const geo = new THREE.PlaneGeometry(40, 40, 80, 80)
    geo.rotateX(-Math.PI / 2)
    const pos = geo.attributes.position
    for (let i = 0; i < pos.count; i++) {
      pos.setY(i, heightAt(pos.getX(i), pos.getZ(i)))
    }
    pos.needsUpdate = true
    geo.computeVertexNormals()
    return geo
  }, [])

  const grass = useMemo(() => {
    const tex = getGrassTexture()
    tex.repeat.set(22, 22)
    return tex
  }, [])

  const soil = useMemo(
    () => new THREE.MeshStandardMaterial({ color: '#4a3222', roughness: 1, metalness: 0 }),
    []
  )

  useFrame((state) => {
    const mat = waterRef.current
    if (!mat) return
    const t = state.clock.elapsedTime
    mat.opacity = 0.7 + Math.sin(t * 1.5) * 0.06
    mat.emissiveIntensity = 0.35 + Math.sin(t * 0.8) * 0.12
  })

  return (
    <group>
      <mesh geometry={geometry} receiveShadow>
        <meshStandardMaterial map={grass} color="#ffffff" roughness={1} metalness={0} />
      </mesh>

      <mesh position={[POND.x, -0.42, POND.z]} rotation={[-Math.PI / 2, 0, 0]}>
        <circleGeometry args={[2.9, 40]} />
        <meshStandardMaterial
          ref={waterRef}
          color="#2f6f8f"
          emissive="#123a4e"
          emissiveIntensity={0.35}
          transparent
          opacity={0.72}
          roughness={0.2}
          metalness={0.25}
          depthWrite={false}
        />
      </mesh>

      {SIDE_WALLS.map((wall, i) => (
        <mesh key={i} position={wall.p} material={soil} receiveShadow>
          <boxGeometry args={wall.s} />
        </mesh>
      ))}
    </group>
  )
}
