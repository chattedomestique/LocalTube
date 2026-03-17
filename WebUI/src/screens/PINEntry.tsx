import { useState, useRef, useCallback, useEffect } from 'react'
import { useAppStore } from '../store'

export default function PINEntry() {
  const { send, setOnPINValidated } = useAppStore()
  const [pin, setPin] = useState('')
  const [shaking, setShaking] = useState(false)
  const [error, setError] = useState(false)
  const [focusedIdx, setFocusedIdx] = useState(-1)
  const inputRef = useRef<HTMLInputElement>(null)

  const digits = pin.split('').concat(Array(4).fill('')).slice(0, 4)
  const cursorIdx = Math.min(pin.length, 3)

  // Auto-focus on mount
  useEffect(() => {
    setTimeout(() => inputRef.current?.focus(), 100)
  }, [])

  useEffect(() => {
    setOnPINValidated((valid: boolean) => {
      if (!valid) {
        setShaking(true)
        setError(true)
        setPin('')
        setTimeout(() => setShaking(false), 600)
      }
    })
    return () => setOnPINValidated(undefined)
  }, [setOnPINValidated])

  // Auto-submit when 4 digits are entered
  useEffect(() => {
    if (pin.length === 4) {
      send({ type: 'validatePIN', payload: { pin } })
    }
  }, [pin, send])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Backspace') {
        setPin(prev => prev.slice(0, -1))
        setError(false)
      }
    },
    []
  )

  const handleInput = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const raw = e.target.value.replace(/\D/g, '')
      setPin(prev => (prev + raw).slice(0, 4))
      setError(false)
      e.target.value = ''
    },
    []
  )

  const handleCancel = () => {
    send({ type: 'exitEditorMode' })
  }

  return (
    <div className="modal-backdrop">
      <div
        className={`modal-panel ${shaking ? 'shake' : ''}`}
        style={{
          width: 360,
          padding: '40px 36px',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 28,
        }}
      >
        {/* Icon */}
        <div style={{
          width: 60,
          height: 60,
          borderRadius: 18,
          background: 'var(--accent-dim)',
          border: '1px solid rgba(155,93,229,0.3)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
            <rect x="5" y="13" width="18" height="12" rx="2.5" fill="var(--accent)" opacity="0.9" />
            <path d="M9 13V10C9 7.24 11.24 5 14 5C16.76 5 19 7.24 19 10V13" stroke="var(--accent)" strokeWidth="2" strokeLinecap="round" fill="none" />
            <circle cx="14" cy="19" r="2" fill="white" />
          </svg>
        </div>

        {/* Title */}
        <div style={{ textAlign: 'center', marginTop: -8 }}>
          <h2 style={{ fontSize: 20, marginBottom: 6 }}>Enter Editor PIN</h2>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
            Enter your 4-digit PIN to unlock editor mode.
          </p>
        </div>

        {/* PIN digits */}
        <div style={{ position: 'relative', width: '100%' }}>
          <div style={{
            display: 'flex',
            gap: 12,
            justifyContent: 'center',
          }}>
            {digits.map((d, i) => (
              <div
                key={i}
                onClick={() => inputRef.current?.focus()}
                style={{
                  width: 56,
                  height: 64,
                  border: '2px solid',
                  borderColor: error
                    ? 'rgba(248,113,113,0.6)'
                    : focusedIdx >= 0 && i === cursorIdx
                      ? 'var(--accent)'
                      : d
                        ? 'var(--border-strong)'
                        : 'var(--border)',
                  borderRadius: 12,
                  background: error ? 'rgba(248,113,113,0.05)' : 'var(--surface-el)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 28,
                  fontWeight: 700,
                  color: error ? 'var(--destructive)' : 'var(--text-primary)',
                  boxShadow: focusedIdx >= 0 && i === cursorIdx && !error
                    ? '0 0 0 3px var(--accent-dim)'
                    : 'none',
                  transition: 'all 0.15s ease',
                  cursor: 'text',
                }}
              >
                {d ? '●' : (
                  focusedIdx >= 0 && i === cursorIdx ? (
                    <div style={{
                      width: 2,
                      height: 28,
                      background: 'var(--accent)',
                      borderRadius: 1,
                      animation: 'pulse-glow 1s ease-in-out infinite',
                    }} />
                  ) : null
                )}
              </div>
            ))}
          </div>

          {/* Hidden input */}
          <input
            ref={inputRef}
            type="number"
            inputMode="numeric"
            pattern="[0-9]*"
            style={{
              position: 'absolute',
              opacity: 0,
              width: '100%',
              height: '100%',
              top: 0,
              left: 0,
              cursor: 'text',
            }}
            onFocus={() => setFocusedIdx(cursorIdx)}
            onBlur={() => setFocusedIdx(-1)}
            onKeyDown={handleKeyDown}
            onChange={handleInput}
          />
        </div>

        {/* Error message */}
        {error && (
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            marginTop: -12,
            padding: '8px 14px',
            background: 'rgba(248,113,113,0.1)',
            border: '1px solid rgba(248,113,113,0.25)',
            borderRadius: 8,
          }}>
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
              <circle cx="7" cy="7" r="6" fill="none" stroke="#f87171" strokeWidth="1.5" />
              <path d="M7 4V7.5" stroke="#f87171" strokeWidth="1.5" strokeLinecap="round" />
              <circle cx="7" cy="10" r="0.75" fill="#f87171" />
            </svg>
            <span style={{ fontSize: 13, color: 'var(--destructive)' }}>
              Incorrect PIN — please try again
            </span>
          </div>
        )}

        {/* Cancel */}
        <button
          className="lt-btn-ghost"
          onClick={handleCancel}
          style={{
            width: '100%',
            justifyContent: 'center',
            color: 'var(--text-secondary)',
          }}
        >
          Cancel
        </button>
      </div>
    </div>
  )
}
