import { useEffect, useRef, useState, type ReactNode } from 'react'

export interface LtSelectOption {
  value: string
  label: string
}

/**
 * Glass dropdown matching the app aesthetic — replaces the native <select>,
 * whose open menu can't be styled and breaks the look. Trigger is a glass
 * pill; the menu is a frosted popover with a check on the active row.
 *
 * Closes on outside-click and Escape. The menu is always mounted (for the
 * open/close transition) but is pointer-inert and invisible when closed.
 */
export default function LtSelect({
  value,
  options,
  onChange,
  label,
  icon,
  minWidth = 150,
  align = 'right',
}: {
  value: string
  options: LtSelectOption[]
  onChange: (value: string) => void
  /** Optional muted prefix inside the trigger, e.g. "Sort". */
  label?: string
  /** Optional leading icon inside the trigger. */
  icon?: ReactNode
  minWidth?: number
  /** Which edge the menu aligns to. */
  align?: 'left' | 'right'
}) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const current = options.find(o => o.value === value) ?? options[0]

  useEffect(() => {
    if (!open) return
    const onDoc = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onDoc)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDoc)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  return (
    <div ref={rootRef} style={{ position: 'relative', display: 'inline-flex' }}>
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          height: 36,
          padding: '0 12px',
          minWidth,
          borderRadius: 10,
          background: open ? 'rgba(255,255,255,0.10)' : 'rgba(255,255,255,0.05)',
          border: `0.5px solid ${open ? 'var(--glass-border-strong)' : 'var(--glass-border)'}`,
          backdropFilter: 'blur(16px) saturate(160%)',
          WebkitBackdropFilter: 'blur(16px) saturate(160%)',
          color: 'var(--text-primary)',
          fontSize: 13,
          fontWeight: 600,
          cursor: 'pointer',
          outline: 'none',
          transition: 'background 160ms ease, border-color 160ms ease',
        }}
      >
        {icon && (
          <span style={{ display: 'flex', color: 'var(--text-tertiary)', flexShrink: 0 }}>{icon}</span>
        )}
        {label && (
          <span style={{ color: 'var(--text-tertiary)', fontWeight: 500, flexShrink: 0 }}>{label}</span>
        )}
        <span style={{ flex: 1, textAlign: 'left' }}>{current?.label}</span>
        <svg
          width="11" height="11" viewBox="0 0 11 11" fill="none"
          style={{
            flexShrink: 0,
            color: 'var(--text-secondary)',
            transform: open ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 180ms ease',
          }}
        >
          <path d="M2.5 4L5.5 7L8.5 4" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {/* Menu */}
      <div
        role="listbox"
        style={{
          position: 'absolute',
          top: 'calc(100% + 6px)',
          left: align === 'left' ? 0 : undefined,
          right: align === 'right' ? 0 : undefined,
          minWidth: '100%',
          zIndex: 80,
          padding: 5,
          borderRadius: 12,
          background: 'rgba(20,20,25,0.97)',
          backdropFilter: 'blur(28px) saturate(180%)',
          WebkitBackdropFilter: 'blur(28px) saturate(180%)',
          border: '0.5px solid var(--glass-border-strong)',
          boxShadow: 'var(--glass-shadow-lg)',
          display: 'flex',
          flexDirection: 'column',
          gap: 2,
          opacity: open ? 1 : 0,
          transform: open ? 'translateY(0) scale(1)' : 'translateY(-4px) scale(0.98)',
          transformOrigin: align === 'right' ? 'top right' : 'top left',
          pointerEvents: open ? 'auto' : 'none',
          transition: 'opacity 160ms ease, transform 180ms cubic-bezier(0.25, 1, 0.5, 1)',
        }}
      >
        {options.map(o => {
          const active = o.value === value
          return (
            <button
              key={o.value}
              type="button"
              role="option"
              aria-selected={active}
              onClick={() => { onChange(o.value); setOpen(false) }}
              onMouseEnter={e => { if (!active) e.currentTarget.style.background = 'rgba(255,255,255,0.06)' }}
              onMouseLeave={e => { if (!active) e.currentTarget.style.background = 'transparent' }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: '8px 10px',
                borderRadius: 8,
                border: 'none',
                background: active ? 'var(--accent-dim)' : 'transparent',
                color: active ? 'var(--accent)' : 'var(--text-secondary)',
                fontSize: 13,
                fontWeight: 600,
                cursor: 'pointer',
                textAlign: 'left',
                whiteSpace: 'nowrap',
                transition: 'background 120ms ease, color 120ms ease',
              }}
            >
              <span style={{ width: 14, display: 'flex', flexShrink: 0 }}>
                {active && (
                  <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                    <path d="M2.5 6.5L5 9L9.5 3.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </span>
              <span style={{ flex: 1 }}>{o.label}</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
