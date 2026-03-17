import type { RefObject, KeyboardEvent, ChangeEvent } from 'react'
import { useState, useRef, useCallback } from 'react'
import { useAppStore } from '../store'

function PINDigitInput({
  value,
  focused,
  inputRef,
}: {
  value: string
  focused: boolean
  inputRef: RefObject<HTMLInputElement | null>
}) {
  return (
    <div style={{
      width: 56,
      height: 64,
      border: '2px solid',
      borderColor: focused ? 'var(--accent)' : value ? 'var(--border-strong)' : 'var(--border)',
      borderRadius: 12,
      background: 'var(--surface-el)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontSize: 28,
      fontWeight: 700,
      color: 'var(--text-primary)',
      boxShadow: focused ? '0 0 0 3px var(--accent-dim)' : 'none',
      transition: 'all 0.15s ease',
      cursor: 'text',
      position: 'relative',
    }} onClick={() => inputRef.current?.focus()}>
      {value ? '●' : (
        focused ? (
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
  )
}

function PINField({
  label,
  value,
  onChange,
  error,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  error?: boolean
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [focusedIdx, setFocusedIdx] = useState(-1)

  const digits = value.split('').concat(Array(4).fill('')).slice(0, 4)
  const cursorIdx = Math.min(value.length, 3)

  const handleKeyDown = useCallback(
    (e: KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Backspace') {
        onChange(value.slice(0, -1))
      }
    },
    [value, onChange]
  )

  const handleInput = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      const raw = e.target.value.replace(/\D/g, '')
      onChange(raw.slice(0, 4))
      e.target.value = ''
    },
    [onChange]
  )

  return (
    <div>
      <label className="lt-label">{label}</label>
      <div style={{ display: 'flex', gap: 12, justifyContent: 'center', position: 'relative' }}>
        {digits.map((d, i) => (
          <PINDigitInput
            key={i}
            value={d}
            focused={focusedIdx >= 0 && i === cursorIdx}
            inputRef={inputRef as React.RefObject<HTMLInputElement | null>}
          />
        ))}
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
      {error && (
        <p style={{
          marginTop: 8,
          fontSize: 13,
          color: 'var(--destructive)',
          textAlign: 'center',
        }}>
          PINs don't match — please try again
        </p>
      )}
    </div>
  )
}

export default function PINSetup() {
  const { send } = useAppStore()
  const [pin, setPin] = useState('')
  const [confirmPin, setConfirmPin] = useState('')
  const [error, setError] = useState(false)
  const [done, setDone] = useState(false)

  const handleSubmit = () => {
    if (pin.length < 4) return
    if (pin !== confirmPin) {
      setError(true)
      setConfirmPin('')
      return
    }
    setError(false)
    send({ type: 'setPIN', payload: { pin } })
    setDone(true)
  }

  if (done) {
    return (
      <div className="screen-enter" style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        height: '100%',
        gap: 16,
      }}>
        <div style={{
          width: 72,
          height: 72,
          borderRadius: '50%',
          background: 'rgba(52,211,153,0.15)',
          border: '2px solid var(--success)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
            <path d="M6 16L13 23L26 9" stroke="#34d399" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h2 style={{ fontSize: 24 }}>PIN Set!</h2>
        <p style={{ color: 'var(--text-secondary)' }}>
          You can now access the editor with your PIN.
        </p>
      </div>
    )
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
        width: 400,
        height: 400,
        borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(155,93,229,0.1) 0%, transparent 70%)',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -60%)',
        pointerEvents: 'none',
      }} />

      {/* Lock icon */}
      <div style={{
        width: 72,
        height: 72,
        borderRadius: 22,
        background: 'var(--surface)',
        border: '1px solid var(--border)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 24,
        boxShadow: 'var(--shadow-md)',
      }}>
        <svg width="36" height="36" viewBox="0 0 36 36" fill="none">
          <rect x="8" y="17" width="20" height="14" rx="3" fill="var(--accent)" opacity="0.9" />
          <path d="M12 17V13C12 9.69 14.69 7 18 7C21.31 7 24 9.69 24 13V17" stroke="var(--accent)" strokeWidth="2.5" strokeLinecap="round" fill="none" />
          <circle cx="18" cy="24" r="2.5" fill="white" />
        </svg>
      </div>

      <h1 style={{ fontSize: 28, marginBottom: 8, textAlign: 'center' }}>
        Set Your Editor PIN
      </h1>
      <p style={{
        fontSize: 14,
        color: 'var(--text-secondary)',
        textAlign: 'center',
        maxWidth: 320,
        marginBottom: 40,
      }}>
        This PIN protects your library settings and channel management.
      </p>

      {/* Form card */}
      <div style={{
        background: 'var(--surface)',
        border: '1px solid var(--border)',
        borderRadius: 20,
        padding: '36px 40px',
        width: 380,
        display: 'flex',
        flexDirection: 'column',
        gap: 28,
      }}>
        <PINField
          label="Create PIN"
          value={pin}
          onChange={(v) => { setPin(v); setError(false) }}
        />
        <PINField
          label="Confirm PIN"
          value={confirmPin}
          onChange={(v) => { setConfirmPin(v); setError(false) }}
          error={error}
        />

        <button
          className="lt-btn-primary"
          onClick={handleSubmit}
          disabled={pin.length < 4 || confirmPin.length < 4}
          style={{
            width: '100%',
            justifyContent: 'center',
            padding: '13px 20px',
            fontSize: 15,
            opacity: pin.length < 4 || confirmPin.length < 4 ? 0.4 : 1,
            cursor: pin.length < 4 || confirmPin.length < 4 ? 'not-allowed' : 'pointer',
          }}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <rect x="3" y="8" width="10" height="7" rx="1.5" fill="white" opacity="0.9" />
            <path d="M5 8V5.5C5 3.57 6.57 2 8.5 2C10.43 2 12 3.57 12 5.5V8" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
          </svg>
          Set PIN
        </button>
      </div>

      <p style={{
        marginTop: 20,
        fontSize: 12,
        color: 'var(--text-tertiary)',
        textAlign: 'center',
      }}>
        Your PIN is stored securely in the macOS keychain.
      </p>
    </div>
  )
}
