import { useState, useEffect } from 'react'
import { useAppStore } from '../store'

export default function Onboarding() {
  const { send, setOnFolderSelected } = useAppStore()
  const [folderPath, setFolderPath] = useState<string | null>(null)
  const [step, setStep] = useState<'welcome' | 'folder' | 'done'>('welcome')

  useEffect(() => {
    setOnFolderSelected((path: string) => {
      setFolderPath(path)
      setStep('done')
    })
    return () => setOnFolderSelected(undefined)
  }, [setOnFolderSelected])

  const handleChooseFolder = () => {
    send({ type: 'openFolderPicker' })
    setStep('folder')
  }

  const handleNext = () => {
    // Trigger PIN setup by dispatching a stateUpdate — in real use the
    // Swift side drives needsPINSetup. Here we just signal readiness.
    send({ type: 'getState' })
  }

  return (
    <div className="screen-enter" style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      background: 'var(--bg)',
      position: 'relative',
      overflow: 'hidden',
    }}>
      {/* Background glow */}
      <div style={{
        position: 'absolute',
        width: 600,
        height: 600,
        borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(155,93,229,0.12) 0%, transparent 70%)',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -60%)',
        pointerEvents: 'none',
      }} />

      {/* Logo mark */}
      <div style={{
        width: 96,
        height: 96,
        borderRadius: 28,
        background: 'linear-gradient(135deg, #9b5de5, #60a5fa)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 32,
        boxShadow: '0 0 40px rgba(155,93,229,0.4)',
      }}>
        <svg width="52" height="52" viewBox="0 0 52 52" fill="none">
          {/* Play button triangle */}
          <polygon
            points="20,14 42,26 20,38"
            fill="white"
            style={{ filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.3))' }}
          />
          {/* Small decorative dots */}
          <circle cx="12" cy="26" r="3" fill="rgba(255,255,255,0.5)" />
          <circle cx="12" cy="16" r="2" fill="rgba(255,255,255,0.3)" />
          <circle cx="12" cy="36" r="2" fill="rgba(255,255,255,0.3)" />
        </svg>
      </div>

      {/* Title */}
      <h1 style={{
        fontSize: 42,
        fontWeight: 700,
        letterSpacing: '-0.03em',
        marginBottom: 12,
        textAlign: 'center',
        lineHeight: 1.1,
      }}>
        <span className="gradient-text">LocalTube</span>
      </h1>

      {/* Tagline */}
      <p style={{
        fontSize: 17,
        color: 'var(--text-secondary)',
        textAlign: 'center',
        maxWidth: 380,
        lineHeight: 1.6,
        marginBottom: 56,
      }}>
        Your personal YouTube library —<br />
        offline, distraction-free.
      </p>

      {/* Steps */}
      <div style={{
        background: 'var(--surface)',
        border: '1px solid var(--border)',
        borderRadius: 20,
        padding: '32px 36px',
        width: 420,
        display: 'flex',
        flexDirection: 'column',
        gap: 24,
      }}>
        {/* Step indicator */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 4 }}>
          {['1', '2'].map((n, i) => (
            <div key={n} style={{
              width: 28,
              height: 28,
              borderRadius: '50%',
              background: i === 0 && step !== 'welcome'
                ? 'var(--success)'
                : i === 0
                  ? 'var(--accent)'
                  : step === 'done'
                    ? 'var(--accent)'
                    : 'var(--surface-el)',
              border: '1px solid',
              borderColor: i === 0 && step !== 'welcome'
                ? 'var(--success)'
                : i === 0
                  ? 'var(--accent)'
                  : step === 'done'
                    ? 'var(--accent)'
                    : 'var(--border)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 12,
              fontWeight: 700,
              color: i === 0 && step !== 'welcome'
                ? '#0d0d0f'
                : 'white',
              transition: 'all 0.3s ease',
            }}>
              {i === 0 && step !== 'welcome' ? (
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M2.5 7L6 10.5L11.5 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              ) : n}
            </div>
          ))}
        </div>

        {/* Step 1: Choose folder */}
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
            <span style={{ fontSize: 20 }}>📁</span>
            <span style={{ fontWeight: 600, fontSize: 15, color: 'var(--text-primary)' }}>
              Choose Download Folder
            </span>
          </div>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14, paddingLeft: 30 }}>
            Select where LocalTube stores your downloaded videos.
          </p>
          {folderPath ? (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              background: 'rgba(52, 211, 153, 0.1)',
              border: '1px solid rgba(52, 211, 153, 0.3)',
              borderRadius: 10,
              padding: '8px 12px',
              marginLeft: 30,
            }}>
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <circle cx="7" cy="7" r="6" fill="#34d399" />
                <path d="M4 7L6.5 9.5L10 5" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <span style={{
                fontSize: 12,
                color: 'var(--success)',
                fontFamily: 'ui-monospace, monospace',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                flex: 1,
              }}>
                {folderPath}
              </span>
              <button
                onClick={handleChooseFolder}
                style={{
                  background: 'none',
                  border: 'none',
                  color: 'var(--text-tertiary)',
                  cursor: 'pointer',
                  fontSize: 12,
                  padding: '2px 6px',
                  borderRadius: 4,
                }}
              >
                Change
              </button>
            </div>
          ) : (
            <button
              className="lt-btn-primary"
              onClick={handleChooseFolder}
              style={{ marginLeft: 30 }}
            >
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M2 4.5C2 3.67 2.67 3 3.5 3H6.25L7.5 4.5H12.5C13.33 4.5 14 5.17 14 6V11.5C14 12.33 13.33 13 12.5 13H3.5C2.67 13 2 12.33 2 11.5V4.5Z" stroke="white" strokeWidth="1.5" fill="none" strokeLinejoin="round" />
              </svg>
              Choose Folder
            </button>
          )}
        </div>

        <div style={{
          height: 1,
          background: 'var(--border)',
          margin: '0 -4px',
        }} />

        {/* Step 2: Continue */}
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
            <span style={{ fontSize: 20 }}>🔐</span>
            <span style={{
              fontWeight: 600,
              fontSize: 15,
              color: step === 'done' ? 'var(--text-primary)' : 'var(--text-tertiary)',
            }}>
              Set Up Editor PIN
            </span>
          </div>
          <p style={{
            fontSize: 13,
            color: step === 'done' ? 'var(--text-secondary)' : 'var(--text-tertiary)',
            marginBottom: 14,
            paddingLeft: 30,
          }}>
            Protect library management behind a PIN.
          </p>
          <button
            className="lt-btn-primary"
            onClick={handleNext}
            disabled={step !== 'done'}
            style={{
              marginLeft: 30,
              opacity: step === 'done' ? 1 : 0.4,
              cursor: step === 'done' ? 'pointer' : 'not-allowed',
            }}
          >
            Continue →
          </button>
        </div>
      </div>

      {/* Footer note */}
      <p style={{
        marginTop: 32,
        fontSize: 12,
        color: 'var(--text-tertiary)',
        textAlign: 'center',
      }}>
        LocalTube stores everything locally — no accounts, no tracking.
      </p>
    </div>
  )
}
