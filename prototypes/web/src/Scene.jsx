import { useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import { PerspectiveCamera } from '@react-three/drei'
import * as THREE from 'three'
import Lighting from './world/Lighting.jsx'
import Terrain, { heightAt } from './world/Terrain.jsx'
import Props from './world/Props.jsx'
import Ranger from './entities/Ranger.jsx'
import { keys } from './input.js'
import { getState } from './store.js'

const CAM_RADIUS = 11
const CAM_HEIGHT = 11
const ROT_STEP = Math.PI / 4

export default function Scene() {
  const camRef = useRef()
  const yaw = useRef(0)
  const targetYaw = useRef(0)
  const prevQ = useRef(false)
  const prevE = useRef(false)
  const lookAt = useRef(new THREE.Vector3())

  useFrame((state, delta) => {
    // Q/E 以 45 度步进旋转相机
    const q = keys.has('KeyQ')
    const e = keys.has('KeyE')
    if (q && !prevQ.current) targetYaw.current += ROT_STEP
    if (e && !prevE.current) targetYaw.current -= ROT_STEP
    prevQ.current = q
    prevE.current = e

    yaw.current = THREE.MathUtils.damp(yaw.current, targetYaw.current, 6, delta)

    const { playerPos } = getState()
    const px = playerPos.x
    const pz = playerPos.z
    const groundY = heightAt(px, pz)

    const tx = px + Math.sin(yaw.current) * CAM_RADIUS
    const tz = pz + Math.cos(yaw.current) * CAM_RADIUS
    const ty = groundY + CAM_HEIGHT

    const cam = camRef.current
    if (!cam) return

    const k = 1 - Math.exp(-4 * delta)
    cam.position.x += (tx - cam.position.x) * k
    cam.position.y += (ty - cam.position.y) * k
    cam.position.z += (tz - cam.position.z) * k

    lookAt.current.set(px, groundY + 1, pz)
    cam.lookAt(lookAt.current)
  })

  return (
    <>
      <PerspectiveCamera
        ref={camRef}
        makeDefault
        fov={28}
        near={0.1}
        far={120}
        position={[0, CAM_HEIGHT, CAM_RADIUS]}
      />
      <Lighting />
      <Terrain />
      <Props />
      <Ranger />
    </>
  )
}
