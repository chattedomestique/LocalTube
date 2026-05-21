import { useState, useEffect, useRef } from 'react'

/**
 * Ambient blurred-image background. Same visual stack as the channel
 * page (two overlapping blurs + dark scrim + pixel noise), but the
 * source rotation is timer-driven instead of scroll-driven so it works
 * on screens that aren't long enough to drive an IntersectionObserver
 * (the library, for example).
 *
 * Layers stack on top of each other; new layers fade in over older
 * ones, which then sit at opacity 1 underneath until they're sliced
 * out of the rolling buffer. This gives a smooth continuous blend
 * with no fade-to-black moments — exactly the pattern used on the
 * channel page.
 */
const MAX_LAYERS = 4
const DEFAULT_CYCLE_MS = 9000
const FADE_MS = 1400

export default function AmbientBackground({
  sources,
  cycleMs = DEFAULT_CYCLE_MS,
}: {
  /** Ordered list of image URLs. Cycled in order; loops at the end. */
  sources: string[]
  cycleMs?: number
}) {
  type Layer = { key: number; src: string }
  const [layers, setLayers] = useState<Layer[]>([])
  const keyRef = useRef(0)
  const idxRef = useRef(0)

  // Seed with the first source whenever the source list changes
  // identity. Pick the first random index so reopening the library
  // doesn't always start on the same banner.
  const sourcesSig = sources.join('|')
  useEffect(() => {
    if (sources.length === 0) {
      setLayers([])
      return
    }
    idxRef.current = Math.floor(Math.random() * sources.length)
    setLayers([{ key: keyRef.current++, src: sources[idxRef.current] }])
  }, [sourcesSig])  // eslint-disable-line react-hooks/exhaustive-deps

  // Rotate. Skipped when there's only one source.
  useEffect(() => {
    if (sources.length <= 1) return
    const t = window.setInterval(() => {
      idxRef.current = (idxRef.current + 1) % sources.length
      const next = sources[idxRef.current]
      setLayers(prev =>
        [...prev, { key: keyRef.current++, src: next }].slice(-MAX_LAYERS)
      )
    }, cycleMs)
    return () => window.clearInterval(t)
  }, [sources, cycleMs])

  if (layers.length === 0) return null

  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 0, pointerEvents: 'none' }}>
      {layers.map(l => (
        <AmbientLayer key={l.key} src={l.src} />
      ))}
      {/* Dark scrim — keeps card text + UI legible regardless of bg */}
      <div style={{
        position: 'absolute',
        inset: 0,
        background: 'rgba(13,13,15,0.68)',
      }} />
      {/* Pixel noise — breaks the heavy blur's color-banding */}
      <div style={{
        position: 'absolute',
        inset: 0,
        opacity: 0.10,
        backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='1' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
        backgroundRepeat: 'repeat',
        backgroundSize: '96px 96px',
      }} />
    </div>
  )
}

function AmbientLayer({ src }: { src: string }) {
  // Two-rAF enter so opacity:0 paints before transitioning to 1 —
  // otherwise React's commit can collapse both into the same paint
  // and skip the fade entirely.
  const [entered, setEntered] = useState(false)
  useEffect(() => {
    let id2: number | null = null
    const id1 = requestAnimationFrame(() => {
      id2 = requestAnimationFrame(() => setEntered(true))
    })
    return () => {
      cancelAnimationFrame(id1)
      if (id2 !== null) cancelAnimationFrame(id2)
    }
  }, [])

  return (
    <div style={{
      position: 'absolute',
      inset: 0,
      opacity: entered ? 1 : 0,
      transition: `opacity ${FADE_MS}ms cubic-bezier(0.4, 0, 0.2, 1)`,
      pointerEvents: 'none',
      willChange: 'opacity',
    }}>
      <img
        src={src}
        alt=""
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          filter: 'blur(64px) saturate(200%) contrast(1.12) brightness(0.85)',
          opacity: 0.52,
          transform: 'scale(1.3)',
          transformOrigin: 'center',
        }}
        onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
      />
      <img
        src={src}
        alt=""
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          filter: 'blur(40px) saturate(240%) brightness(1.15) hue-rotate(22deg)',
          opacity: 0.18,
          transform: 'scale(1.3) rotate(180deg)',
          transformOrigin: 'center',
          mixBlendMode: 'screen',
        }}
        onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
      />
    </div>
  )
}
