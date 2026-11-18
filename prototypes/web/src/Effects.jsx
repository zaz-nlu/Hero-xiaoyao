import {
  Bloom,
  EffectComposer,
  TiltShift2,
  ToneMapping,
  Vignette,
} from '@react-three/postprocessing'
import { ToneMappingMode } from 'postprocessing'

export default function Effects() {
  return (
    <EffectComposer multisampling={0}>
      <TiltShift2
        blur={0.4}
        taper={0.4}
        start={[0, 0.5]}
        end={[1, 0.5]}
        direction={[1, 0]}
      />
      <Bloom luminanceThreshold={0.7} luminanceSmoothing={0.2} intensity={0.6} mipmapBlur />
      <Vignette darkness={0.55} />
      <ToneMapping mode={ToneMappingMode.ACES_FILMIC} />
    </EffectComposer>
  )
}
