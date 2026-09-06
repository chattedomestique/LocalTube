import { useEffect } from 'react'
import { useAppStore, type Toast } from '../store'

const AUTO_DISMISS_MS = 6000

/**
 * Bottom-centre stack of transient messages ("Video re-queued", "Library
 * moved", "Banner upload failed"). Swift pushes them via the `toast`
 * bridge event; screens can also call `showToast` locally.
 */
export default function ToastHost() {
  const { toasts, dismissToast } = useAppStore()
  if (toasts.length === 0) return null
  return (
    <div
      aria-live="polite"
      style={{
        position: 'fixed',
        left: 0,
        right: 0,
        bottom: 28,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 8,
        zIndex: 400,
        pointerEvents: 'none',
      }}
    >
      {toasts.map(t => <ToastItem key={t.id} toast={t} onDismiss={() => dismissToast(t.id)} />)}
    </div>
  )
}

function ToastItem({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  useEffect(() => {
    const id = window.setTimeout(onDismiss, AUTO_DISMISS_MS)
    return () => window.clearTimeout(id)
  }, [onDismiss])

  const palette = {
    info:    { rgb: '96,165,250',  fg: '#bfdbfe' },
    success: { rgb: '52,211,153', fg: '#a7f3d0' },
    warning: { rgb: '251,191,36', fg: '#fde68a' },
    error:   { rgb: '248,113,113', fg: '#fca5a5' },
  }[toast.kind]

  return (
    <div
      role="status"
      onClick={onDismiss}
      style={{
        pointerEvents: 'auto',
        maxWidth: 640,
        padding: '10px 16px',
        borderRadius: 12,
        background: 'rgba(20,20,25,0.92)',
        backdropFilter: 'blur(16px)',
        WebkitBackdropFilter: 'blur(16px)',
        border: `1px solid rgba(${palette.rgb},0.45)`,
        boxShadow: '0 8px 24px rgba(0,0,0,0.45)',
        color: palette.fg,
        fontSize: 14,
        lineHeight: 1.4,
        cursor: 'pointer',
        animation: 'modalIn 200ms ease forwards',
      }}
    >
      {toast.message}
    </div>
  )
}
