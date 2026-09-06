import { useState } from 'react'
import { useAppStore } from '../store'

/**
 * Shown when a library folder is configured but can't be reached right
 * now — an external drive that isn't plugged in, a network share that's
 * offline. Swift polls the folder every few seconds and clears this
 * screen automatically once it's back; the buttons are for the impatient
 * (Retry) and for people who moved the library somewhere else (Locate).
 *
 * Previously this situation reset the download folder and showed
 * onboarding, so a parent would pick a fresh folder and every existing
 * video was orphaned.
 */
export default function LibraryUnavailable() {
  const { state, send } = useAppStore()
  const [checking, setChecking] = useState(false)
  const path = state.settings.downloadFolderPath ?? ''

  const handleRetry = () => {
    setChecking(true)
    send({ type: 'recheckLibraryFolder' })
    window.setTimeout(() => setChecking(false), 1500)
  }

  return (
    <div className="screen-enter" style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      background: 'var(--bg)',
      gap: 18,
      padding: 40,
      textAlign: 'center',
    }}>
      <div style={{
        width: 96,
        height: 96,
        borderRadius: 28,
        background: 'rgba(251,191,36,0.10)',
        border: '1px solid rgba(251,191,36,0.35)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <svg width="44" height="44" viewBox="0 0 24 24" fill="none">
          <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2h7.5A2.5 2.5 0 0 1 21 9.5v8A2.5 2.5 0 0 1 18.5 20h-13A2.5 2.5 0 0 1 3 17.5v-10Z" stroke="#fbbf24" strokeWidth="1.6" strokeLinejoin="round" />
          <path d="M12 10.5V14" stroke="#fbbf24" strokeWidth="1.8" strokeLinecap="round" />
          <circle cx="12" cy="16.8" r="1" fill="#fbbf24" />
        </svg>
      </div>
      <h1 style={{ fontSize: 34, fontWeight: 800, letterSpacing: '-0.02em' }}>Library folder not found</h1>
      <p style={{ fontSize: 18, color: 'var(--text-secondary)', maxWidth: 560, lineHeight: 1.5 }}>
        LocalTube can't reach the folder that holds your videos. If it's on an external
        drive, plug it in — this screen will go away by itself. Nothing has been changed.
      </p>
      <code style={{
        fontSize: 14,
        fontFamily: 'ui-monospace, monospace',
        color: 'var(--text-tertiary)',
        background: 'rgba(255,255,255,0.05)',
        border: '1px solid rgba(255,255,255,0.1)',
        borderRadius: 8,
        padding: '8px 14px',
        maxWidth: 640,
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
      }}>
        {path}
      </code>
      <div style={{ display: 'flex', gap: 10, marginTop: 8 }}>
        <button className="lt-btn-primary" onClick={handleRetry} disabled={checking}>
          {checking ? 'Checking…' : 'Try Again'}
        </button>
        <button className="lt-btn-secondary" onClick={() => send({ type: 'chooseLibraryFolder' })}>
          Locate Library…
        </button>
      </div>
      <p style={{ fontSize: 13, color: 'var(--text-tertiary)', maxWidth: 520 }}>
        Use "Locate Library…" if you moved the videos to a different folder or drive.
        Downloads are paused until the folder is reachable.
      </p>
    </div>
  )
}
