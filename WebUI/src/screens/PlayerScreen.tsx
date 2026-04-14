import { useState, useEffect, useRef, useCallback, type ReactNode } from 'react'

// ── Types ────────────────────────────────────────────────────────────────────

interface PlayerState {
  isPlaying: boolean
  currentTime: number
  duration: number
  title: string
}

// Swift injects window.LocalTubePlayer before the page loads.
declare global {
  interface Window {
    LocalTubePlayer?: {
      on:       (type: string, fn: (payload: unknown) => void) => void
      dispatch: (event: { type: string; payload: unknown }) => void
      send:     (msg: Record<string, unknown>) => void
    }
    __playerMode?: boolean
  }
}

function sendCommand(command: string, value?: number) {
  window.LocalTubePlayer?.send(value !== undefined ? { command, value } : { command })
}

function formatTime(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '0:00'
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${m}:${String(s).padStart(2, '0')}`
}

// ── Icons ────────────────────────────────────────────────────────────────────

function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" width="30" height="30" fill="white">
      <path d="M8 5.14v13.72c0 .75.82 1.2 1.46.8l10.04-6.86a.96.96 0 000-1.6L9.46 4.34A.96.96 0 008 5.14z" />
    </svg>
  )
}

function PauseIcon() {
  return (
    <svg viewBox="0 0 24 24" width="30" height="30" fill="white">
      <rect x="5" y="4" width="4.5" height="16" rx="1.5" />
      <rect x="14.5" y="4" width="4.5" height="16" rx="1.5" />
    </svg>
  )
}

function SkipBackIcon() {
  return (
    <svg viewBox="0 0 28 28" width="24" height="24" fill="white">
      {/* Counterclockwise arc arrow */}
      <path d="M14 5.5V2l-5 5 5 5V8.6c3.5.5 6.2 3.5 6.2 7.2 0 4-3.2 7.2-7.2 7.2S5.8 19.8 5.8 15.8H3.6c0 5.7 4.6 10.4 10.4 10.4S24.4 21.5 24.4 15.8c0-5.4-4.1-9.9-9.4-10.3z" />
      <text x="14" y="19" textAnchor="middle" fontSize="6.5" fontWeight="700" fontFamily="-apple-system, system-ui, sans-serif" fill="white">10</text>
    </svg>
  )
}

function SkipForwardIcon() {
  return (
    <svg viewBox="0 0 28 28" width="24" height="24" fill="white">
      {/* Clockwise arc arrow */}
      <path d="M14 5.5V2l5 5-5 5V8.6C10.5 9.1 7.8 12.1 7.8 15.8c0 4 3.2 7.2 7.2 7.2s7.2-3.2 7.2-7.2h2.2c0 5.7-4.6 10.4-10.4 10.4S3.6 21.5 3.6 15.8c0-5.4 4.1-9.9 9.4-10.3z" />
      <text x="14" y="19" textAnchor="middle" fontSize="6.5" fontWeight="700" fontFamily="-apple-system, system-ui, sans-serif" fill="white">10</text>
    </svg>
  )
}

function BackArrowIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="white">
      <path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" />
    </svg>
  )
}

// ── Scrub Bar ────────────────────────────────────────────────────────────────

interface ScrubBarProps {
  progress: number
  onSeek: (progress: number) => void
  onScrubStart: () => void
  onScrubEnd: () => void
}

function ScrubBar({ progress, onSeek, onScrubStart, onScrubEnd }: ScrubBarProps) {
  const trackRef = useRef<HTMLDivElement>(null)
  const [hovered, setHovered] = useState(false)
  const [dragging, setDragging] = useState(false)
  const [dragProgress, setDragProgress] = useState(0)

  const getProgressFromEvent = useCallback((e: MouseEvent | React.MouseEvent) => {
    if (!trackRef.current) return 0
    const rect = trackRef.current.getBoundingClientRect()
    return Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
  }, [])

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    const p = getProgressFromEvent(e)
    setDragging(true)
    setDragProgress(p)
    onScrubStart()
    onSeek(p)
  }, [getProgressFromEvent, onSeek, onScrubStart])

  useEffect(() => {
    if (!dragging) return
    const onMove = (e: MouseEvent) => {
      const p = getProgressFromEvent(e)
      setDragProgress(p)
      onSeek(p)
    }
    const onUp = () => {
      setDragging(false)
      onScrubEnd()
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
    return () => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
  }, [dragging, getProgressFromEvent, onSeek, onScrubEnd])

  const displayProgress = dragging ? dragProgress : progress
  const active = hovered || dragging

  return (
    <div
      ref={trackRef}
      onMouseDown={handleMouseDown}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => { if (!dragging) setHovered(false) }}
      style={{
        position: 'relative',
        flex: 1,
        height: 28,
        display: 'flex',
        alignItems: 'center',
        cursor: 'pointer',
        userSelect: 'none',
      }}
    >
      {/* Track */}
      <div style={{
        position: 'absolute',
        left: 0, right: 0,
        height: active ? 8 : 4,
        borderRadius: 99,
        background: 'rgba(255,255,255,0.28)',
        transition: 'height 160ms cubic-bezier(0.89,0,0.14,1)',
        overflow: 'hidden',
      }}>
        {/* Fill */}
        <div style={{
          position: 'absolute',
          top: 0, left: 0, bottom: 0,
          width: `${displayProgress * 100}%`,
          borderRadius: 99,
          background: 'rgba(162,100,232,1)',
          transition: dragging ? 'none' : 'width 80ms linear',
        }} />
      </div>
      {/* Knob */}
      <div style={{
        position: 'absolute',
        left: `${displayProgress * 100}%`,
        transform: 'translateX(-50%)',
        width: 16,
        height: 16,
        borderRadius: '50%',
        background: 'white',
        boxShadow: '0 2px 8px rgba(0,0,0,0.5)',
        opacity: active ? 1 : 0,
        transition: 'opacity 160ms cubic-bezier(0.89,0,0.14,1)',
        pointerEvents: 'none',
      }} />
    </div>
  )
}

// ── Transport Button ─────────────────────────────────────────────────────────

interface TransportBtnProps {
  onClick: () => void
  size?: number
  children: ReactNode
}

function TransportBtn({ onClick, size = 84, children }: TransportBtnProps) {
  const [pressed, setPressed] = useState(false)
  const [hovered, setHovered] = useState(false)

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => { setHovered(false); setPressed(false) }}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => { setPressed(false); onClick() }}
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: pressed
          ? 'rgba(255,255,255,0.38)'
          : hovered
          ? 'rgba(255,255,255,0.26)'
          : 'rgba(255,255,255,0.16)',
        backdropFilter: 'blur(32px) saturate(200%)',
        WebkitBackdropFilter: 'blur(32px) saturate(200%)',
        border: hovered
          ? '1px solid rgba(255,255,255,0.5)'
          : '1px solid rgba(255,255,255,0.24)',
        // Layered shadow: inner top-edge highlight (glass catching light) +
        // outer drop shadow for depth
        boxShadow: pressed
          ? 'inset 0 1px 1px rgba(255,255,255,0.15), 0 2px 8px rgba(0,0,0,0.4)'
          : hovered
          ? 'inset 0 1px 1px rgba(255,255,255,0.3), 0 8px 28px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.08)'
          : 'inset 0 1px 1px rgba(255,255,255,0.2), 0 4px 16px rgba(0,0,0,0.4)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        cursor: 'pointer',
        userSelect: 'none',
        transform: `scale(${pressed ? 0.88 : hovered ? 1.06 : 1})`,
        transition: pressed
          ? 'transform 90ms cubic-bezier(0.4,0,0.2,1), background 90ms cubic-bezier(0.4,0,0.2,1), box-shadow 90ms cubic-bezier(0.4,0,0.2,1), border-color 90ms cubic-bezier(0.4,0,0.2,1)'
          : 'transform 220ms cubic-bezier(0.34,1.2,0.64,1), background 180ms cubic-bezier(0.4,0,0.2,1), box-shadow 180ms cubic-bezier(0.4,0,0.2,1), border-color 180ms cubic-bezier(0.4,0,0.2,1)',
      }}
    >
      {children}
    </div>
  )
}

// ── Back Button ──────────────────────────────────────────────────────────────

function BackButton({ onClick }: { onClick: () => void }) {
  const [hovered, setHovered] = useState(false)
  const [pressed, setPressed] = useState(false)

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => { setHovered(false); setPressed(false) }}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => { setPressed(false); onClick() }}
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: 44,
        height: 36,
        borderRadius: 10,
        background: pressed
          ? 'rgba(255,255,255,0.28)'
          : hovered
          ? 'rgba(255,255,255,0.18)'
          : 'rgba(255,255,255,0.08)',
        backdropFilter: 'blur(24px) saturate(180%)',
        WebkitBackdropFilter: 'blur(24px) saturate(180%)',
        border: hovered
          ? '1px solid rgba(255,255,255,0.36)'
          : '1px solid rgba(255,255,255,0.14)',
        boxShadow: hovered
          ? 'inset 0 1px 1px rgba(255,255,255,0.2), 0 4px 14px rgba(0,0,0,0.4)'
          : 'inset 0 1px 1px rgba(255,255,255,0.12)',
        cursor: 'pointer',
        userSelect: 'none',
        flexShrink: 0,
        transform: `scale(${pressed ? 0.88 : hovered ? 1.06 : 1})`,
        transition: pressed
          ? 'transform 90ms cubic-bezier(0.4,0,0.2,1), background 90ms cubic-bezier(0.4,0,0.2,1), box-shadow 90ms cubic-bezier(0.4,0,0.2,1), border-color 90ms cubic-bezier(0.4,0,0.2,1)'
          : 'transform 220ms cubic-bezier(0.34,1.2,0.64,1), background 180ms cubic-bezier(0.4,0,0.2,1), box-shadow 180ms cubic-bezier(0.4,0,0.2,1), border-color 180ms cubic-bezier(0.4,0,0.2,1)',
      }}
    >
      <BackArrowIcon />
    </div>
  )
}

// ── Player Screen ────────────────────────────────────────────────────────────

const HIDE_DELAY_MS = 4000

export default function PlayerScreen() {
  const [playerState, setPlayerState] = useState<PlayerState>({
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    title: '',
  })
  const [controlsVisible, setControlsVisible] = useState(true)
  const [scrubbing, setScrubbing] = useState(false)
  const hideTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined)

  // Make html/body transparent so the AVPlayerView underneath shows through.
  // index.css sets body { background: var(--bg) } which paints over the native
  // video layer. Resetting it here lets the WKWebView drawsBackground=false work.
  useEffect(() => {
    document.documentElement.style.background = 'transparent'
    document.body.style.background = 'transparent'
    return () => {
      document.documentElement.style.background = ''
      document.body.style.background = ''
    }
  }, [])

  // ── Controls visibility ────────────────────────────────────────────────

  const showControls = useCallback(() => {
    setControlsVisible(true)
    clearTimeout(hideTimerRef.current)
    hideTimerRef.current = setTimeout(() => setControlsVisible(false), HIDE_DELAY_MS)
  }, [])

  const keepControlsVisible = useCallback(() => {
    setControlsVisible(true)
    clearTimeout(hideTimerRef.current)
  }, [])

  // ── Bridge setup ───────────────────────────────────────────────────────

  useEffect(() => {
    window.LocalTubePlayer?.on('playerState', (payload) => {
      setPlayerState(payload as PlayerState)
    })
    // Tell Swift we're ready — triggers an immediate state push
    sendCommand('playerReady')

    // Auto-show controls on start
    showControls()

    return () => clearTimeout(hideTimerRef.current)
  }, [showControls])

  // ── Keyboard handling ──────────────────────────────────────────────────

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // Let the browser handle text input if focused
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      switch (e.code) {
        case 'Escape':      e.preventDefault(); sendCommand('close'); return
        case 'Space':       e.preventDefault(); sendCommand('toggle'); break
        case 'ArrowLeft':   e.preventDefault(); sendCommand('seekBack'); break
        case 'ArrowRight':  e.preventDefault(); sendCommand('seekForward'); break
        case 'ArrowUp':     e.preventDefault(); return
        case 'ArrowDown':   e.preventDefault(); return
        default: return
      }
      showControls()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [showControls])

  // ── Event handlers ─────────────────────────────────────────────────────

  const handleBackgroundClick = () => {
    if (scrubbing) return
    sendCommand('toggle')
    showControls()
  }

  const handleSeek = (progress: number) => {
    sendCommand('seek', progress)
  }

  const handleScrubStart = () => {
    setScrubbing(true)
    keepControlsVisible()
  }

  const handleScrubEnd = () => {
    setScrubbing(false)
    showControls()
  }

  const margin = 48
  const progress = playerState.duration > 0 ? playerState.currentTime / playerState.duration : 0

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        // rgba(0,0,0,0.001) is visually transparent but registers as a painted
        // surface in macOS hit-testing. Without it, WKWebView doesn't deliver
        // mousemove events on fully-transparent layers.
        background: 'rgba(0,0,0,0.001)',
        userSelect: 'none',
        WebkitUserSelect: 'none',
      }}
    >
      {/* Invisible video-area click target — also handles mousemove so
          controls reveal on any motion, not just clicks */}
      <div
        onClick={handleBackgroundClick}
        onMouseMove={showControls}
        style={{
          position: 'absolute',
          inset: 0,
          cursor: controlsVisible ? 'default' : 'none',
        }}
      />

      {/* Controls overlay — fades in/out */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: controlsVisible ? 1 : 0,
          transition: 'opacity 400ms cubic-bezier(0.89,0,0.14,1)',
          pointerEvents: controlsVisible ? 'auto' : 'none',
        }}
      >
        {/* ── Top bar ──────────────────────────────────────────────────── */}
        <div style={{
          position: 'absolute',
          top: 0, left: 0, right: 0,
          height: 160,
          background: 'linear-gradient(to bottom, rgba(0,0,0,0.72) 0%, rgba(0,0,0,0.48) 40%, rgba(0,0,0,0.18) 72%, transparent 100%)',
          display: 'flex',
          alignItems: 'flex-start',
          paddingTop: margin - 8,
          paddingLeft: margin,
          paddingRight: margin,
          gap: 14,
          boxSizing: 'border-box',
        }}>
          <BackButton onClick={() => sendCommand('close')} />
          <div style={{
            color: 'white',
            fontSize: 22,
            fontWeight: 600,
            lineHeight: '36px',
            flex: 1,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            letterSpacing: '-0.3px',
          }}>
            {playerState.title}
          </div>
        </div>

        {/* ── Centre transport buttons ──────────────────────────────────── */}
        <div style={{
          position: 'absolute',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          display: 'flex',
          alignItems: 'center',
          gap: 44,
        }}>
          <TransportBtn size={66} onClick={() => { sendCommand('seekBack'); showControls() }}>
            <SkipBackIcon />
          </TransportBtn>

          <TransportBtn size={84} onClick={() => { sendCommand('toggle'); showControls() }}>
            {playerState.isPlaying ? <PauseIcon /> : <PlayIcon />}
          </TransportBtn>

          <TransportBtn size={66} onClick={() => { sendCommand('seekForward'); showControls() }}>
            <SkipForwardIcon />
          </TransportBtn>
        </div>

        {/* ── Bottom bar ───────────────────────────────────────────────── */}
        <div style={{
          position: 'absolute',
          bottom: 0, left: 0, right: 0,
          height: 170,
          background: 'linear-gradient(to top, rgba(0,0,0,0.75) 0%, rgba(0,0,0,0.52) 35%, rgba(0,0,0,0.22) 68%, transparent 100%)',
          display: 'flex',
          alignItems: 'flex-end',
          paddingBottom: margin - 8,
          paddingLeft: margin,
          paddingRight: margin,
          boxSizing: 'border-box',
          gap: 20,
        }}>
          {/* Current time */}
          <div style={{
            color: 'rgba(255,255,255,0.9)',
            fontSize: 20,
            fontWeight: 500,
            fontVariantNumeric: 'tabular-nums',
            lineHeight: '28px',
            flexShrink: 0,
            fontFamily: '-apple-system, system-ui, sans-serif',
            letterSpacing: '0.2px',
          }}>
            {formatTime(playerState.currentTime)}
          </div>

          {/* Scrub bar */}
          <div style={{ flex: 1, display: 'flex', alignItems: 'center' }}>
            <ScrubBar
              progress={progress}
              onSeek={handleSeek}
              onScrubStart={handleScrubStart}
              onScrubEnd={handleScrubEnd}
            />
          </div>

          {/* Duration */}
          <div style={{
            color: 'rgba(255,255,255,0.9)',
            fontSize: 20,
            fontWeight: 500,
            fontVariantNumeric: 'tabular-nums',
            lineHeight: '28px',
            flexShrink: 0,
            fontFamily: '-apple-system, system-ui, sans-serif',
            letterSpacing: '0.2px',
          }}>
            {formatTime(playerState.duration)}
          </div>
        </div>
      </div>
    </div>
  )
}
