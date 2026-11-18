import { useLayoutEffect, useMemo, useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'
import { getFlowerTexture, getRockTexture, getTreeTexture } from '../art/pixel.js'
import { POND, heightAt } from './Terrain.jsx'

// ---------------------------------------------------------------------------
// 固定种子的伪随机，保证每次布局一致
// ---------------------------------------------------------------------------
function mulberry32(seed) {
  let a = seed >>> 0
  return function () {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const rand = mulberry32(20240517)
const range = (a, b) => a + rand() * (b - a)

function placeItems(count, rMin, rMax, pondClear) {
  const out = []
  let guard = 0
  while (out.length < count && guard < count * 60) {
    guard++
    const angle = rand() * Math.PI * 2
    const radius = range(rMin, rMax)
    const x = Math.cos(angle) * radius
    const z = Math.sin(angle) * radius
    if (Math.hypot(x, z) < 6) continue
    if (Math.hypot(x - POND.x, z - POND.z) < pondClear) continue
    out.push({ x, z })
  }
  return out
}

export const TREES = placeItems(60, 9.5, 18.5, POND.r + 1.6).map((it) => ({
  x: it.x,
  z: it.z,
  scale: range(0.8, 1.25),
}))

export const ROCKS = placeItems(25, 7.5, 17.5, POND.r + 1.2).map((it) => {
  const scale = range(0.6, 1.15)
  return {
    x: it.x,
    z: it.z,
    scale,
    radius: 0.6 * scale,
    rotX: range(-0.4, 0.4),
    rotY: rand() * Math.PI * 2,
    rotZ: range(-0.4, 0.4),
  }
})

const FLOWERS = placeItems(80, 6.5, 17, POND.r + 0.4).map((it) => ({
  x: it.x,
  z: it.z,
  scale: range(0.7, 1.3),
}))

// ---------------------------------------------------------------------------
// 通用竖立 billboard 实例组（只绕 Y 轴转向相机）
// ---------------------------------------------------------------------------
function BillboardField({ items, texture, width, height }) {
  const meshRef = useRef()
  const dummy = useMemo(() => new THREE.Object3D(), [])

  const geometry = useMemo(() => {
    const geo = new THREE.PlaneGeometry(width, height)
    geo.translate(0, height / 2, 0)
    return geo
  }, [width, height])

  const material = useMemo(
    () =>
      new THREE.MeshStandardMaterial({
        map: texture,
        alphaTest: 0.5,
        transparent: false,
        side: THREE.DoubleSide,
        roughness: 1,
        metalness: 0,
      }),
    [texture]
  )

  const depthMaterial = useMemo(
    () =>
      new THREE.MeshDepthMaterial({
        depthPacking: THREE.RGBADepthPacking,
        map: texture,
        alphaTest: 0.5,
        side: THREE.DoubleSide,
      }),
    [texture]
  )

  useFrame(({ camera }) => {
    const mesh = meshRef.current
    if (!mesh) return
    for (let i = 0; i < items.length; i++) {
      const it = items[i]
      dummy.position.set(it.x, heightAt(it.x, it.z), it.z)
      dummy.rotation.set(0, Math.atan2(camera.position.x - it.x, camera.position.z - it.z), 0)
      dummy.scale.setScalar(it.scale || 1)
      dummy.updateMatrix()
      mesh.setMatrixAt(i, dummy.matrix)
    }
    mesh.instanceMatrix.needsUpdate = true
  })

  return (
    <instancedMesh
      ref={meshRef}
      args={[geometry, material, items.length]}
      castShadow
      customDepthMaterial={depthMaterial}
      frustumCulled={false}
    />
  )
}

// ---------------------------------------------------------------------------
// 岩石：低面数 3D + 岩石纹理
// ---------------------------------------------------------------------------
function RockField() {
  const meshRef = useRef()
  const dummy = useMemo(() => new THREE.Object3D(), [])
  const geometry = useMemo(() => new THREE.IcosahedronGeometry(0.55, 0), [])
  const texture = useMemo(() => getRockTexture(), [])
  const material = useMemo(
    () =>
      new THREE.MeshStandardMaterial({
        map: texture,
        roughness: 1,
        metalness: 0,
        flatShading: true,
      }),
    [texture]
  )

  useLayoutEffect(() => {
    const mesh = meshRef.current
    if (!mesh) return
    ROCKS.forEach((rock, i) => {
      dummy.position.set(rock.x, heightAt(rock.x, rock.z) + 0.22 * rock.scale, rock.z)
      dummy.rotation.set(rock.rotX, rock.rotY, rock.rotZ)
      dummy.scale.setScalar(rock.scale)
      dummy.updateMatrix()
      mesh.setMatrixAt(i, dummy.matrix)
    })
    mesh.instanceMatrix.needsUpdate = true
    mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage)
  }, [dummy])

  return (
    <instancedMesh
      ref={meshRef}
      args={[geometry, material, ROCKS.length]}
      castShadow
      receiveShadow
      frustumCulled={false}
    />
  )
}

export default function Props() {
  const treeTexture = useMemo(() => getTreeTexture(), [])
  const flowerTexture = useMemo(() => getFlowerTexture(), [])

  return (
    <group>
      <BillboardField items={TREES} texture={treeTexture} width={3.2} height={4.8} />
      <BillboardField items={FLOWERS} texture={flowerTexture} width={0.8} height={0.8} />
      <RockField />
    </group>
  )
}
