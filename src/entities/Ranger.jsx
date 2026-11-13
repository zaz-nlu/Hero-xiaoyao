import { useMemo, useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'
import { getRangerFrames } from '../art/pixel.js'
import { getMoveVector, isRunning } from '../input.js'
import { setPlayerPos } from '../store.js'
import { POND, heightAt } from '../world/Terrain.jsx'
import { ROCKS } from '../world/Props.jsx'

const SPEED = 4.5
const RUN_MULT = 1.6
const FRAME_TIME = 0.12
const WORLD_LIMIT = 18

const ROW_OF = { down: 0, up: 1, left: 2, right: 3 }

function resolveCollisions(pos) {
  pos.x = THREE.MathUtils.clamp(pos.x, -WORLD_LIMIT, WORLD_LIMIT)
  pos.z = THREE.MathUtils.clamp(pos.z, -WORLD_LIMIT, WORLD_LIMIT)

  // 池塘：圆形推出
  let dx = pos.x - POND.x
  let dz = pos.z - POND.z
  let d = Math.hypot(dx, dz)
  if (d < POND.collide) {
    if (d < 0.0001) {
      dx = 1
      dz = 0
      d = 1
    }
    pos.x = POND.x + (dx / d) * POND.collide
    pos.z = POND.z + (dz / d) * POND.collide
  }

  // 岩石：圆形推出
  for (let i = 0; i < ROCKS.length; i++) {
    const rock = ROCKS[i]
    dx = pos.x - rock.x
    dz = pos.z - rock.z
    d = Math.hypot(dx, dz)
    const minDist = rock.radius + 0.35
    if (d < minDist) {
      if (d < 0.0001) {
        dx = 1
        dz = 0
        d = 1
      }
      pos.x = rock.x + (dx / d) * minDist
      pos.z = rock.z + (dz / d) * minDist
    }
  }

  pos.x = THREE.MathUtils.clamp(pos.x, -WORLD_LIMIT, WORLD_LIMIT)
  pos.z = THREE.MathUtils.clamp(pos.z, -WORLD_LIMIT, WORLD_LIMIT)
}

export default function Ranger() {
  const groupRef = useRef()
  const shadowRef = useRef()

  const sheet = useMemo(() => getRangerFrames(), [])

  const texture = useMemo(() => {
    const tex = sheet.texture.clone()
    tex.needsUpdate = true
    tex.repeat.set(1 / sheet.cols, 1 / sheet.rows)
    tex.wrapS = THREE.ClampToEdgeWrapping
    tex.wrapT = THREE.ClampToEdgeWrapping
    tex.offset.set(0, 1 - 1 / sheet.rows)
    return tex
  }, [sheet])

  const material = useMemo(
    () =>
      new THREE.MeshStandardMaterial({
        map: texture,
        alphaTest: 0.5,
        transparent: false,
        side: THREE.DoubleSide,
        roughness: 0.9,
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

  const geometry = useMemo(() => {
    const geo = new THREE.PlaneGeometry(1.5, 2)
    geo.translate(0, 1, 0) // 脚底对齐地面
    return geo
  }, [])

  const state = useRef({
    x: 0,
    z: 0,
    dir: 'down',
    frame: 0,
    lastDir: null,
    anim: 0,
  })

  useFrame(({ camera }, delta) => {
    const s = state.current
    const input = getMoveVector()
    const len = Math.hypot(input.x, input.z)
    const moving = len > 0.001

    if (moving) {
      // 相机相对移动：屏幕上的“上”始终远离相机
      const camDx = s.x - camera.position.x
      const camDz = s.z - camera.position.z
      const camLen = Math.hypot(camDx, camDz) || 1
      const fx = camDx / camLen
      const fz = camDz / camLen
      const rx = -fz
      const rz = fx

      let wx = fx * -input.z + rx * input.x
      let wz = fz * -input.z + rz * input.x
      const wl = Math.hypot(wx, wz) || 1
      wx /= wl
      wz /= wl

      const speed = SPEED * (isRunning() ? RUN_MULT : 1)
      s.x += wx * speed * delta
      s.z += wz * speed * delta

      // 精灵方向相对相机：远离相机 = up（背面），靠近 = down（正面）
      const forwardAmount = wx * fx + wz * fz
      const rightAmount = wx * rx + wz * rz
      if (Math.abs(forwardAmount) >= Math.abs(rightAmount)) {
        s.dir = forwardAmount >= 0 ? 'up' : 'down'
      } else {
        s.dir = rightAmount >= 0 ? 'right' : 'left'
      }

      s.anim += delta
    } else {
      s.anim = 0
    }

    resolveCollisions(s)

    const frame = moving ? Math.floor(s.anim / FRAME_TIME) % sheet.cols : 0
    if (frame !== s.frame || s.dir !== s.lastDir) {
      s.frame = frame
      s.lastDir = s.dir
      texture.offset.set(frame / sheet.cols, 1 - (ROW_OF[s.dir] + 1) / sheet.rows)
    }

    const groundY = heightAt(s.x, s.z)
    const group = groupRef.current
    if (group) {
      group.position.set(s.x, groundY, s.z)
      group.rotation.y = Math.atan2(camera.position.x - s.x, camera.position.z - s.z)
    }
    if (shadowRef.current) {
      shadowRef.current.position.y = 0.02
    }

    setPlayerPos(s.x, s.z)
  })

  return (
    <group ref={groupRef}>
      <mesh
        geometry={geometry}
        material={material}
        castShadow
        customDepthMaterial={depthMaterial}
        frustumCulled={false}
      />

      {/* 贴地假阴影 */}
      <mesh ref={shadowRef} rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.02, 0]}>
        <circleGeometry args={[0.55, 20]} />
        <meshBasicMaterial color="#000000" transparent opacity={0.28} depthWrite={false} />
      </mesh>
    </group>
  )
}
