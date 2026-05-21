import { useState, type ReactNode } from 'react'
import { useAppStore } from '../store'
import type { NavScreen } from '../types'

/**
 * Single unified shell for ALL editor-mode surfaces. Replaces the
 * previous tangle where Editor, Profiles, and Settings each had their
 * own top bar + back-to-library button, and where the Library top bar
 * tried to double as an editor entry point with a redundant "Manage"
 * button.
 *
 * Navigation model:
 *   - Three sibling tabs: Channels | Profiles | Settings
 *   - Click a tab → navigateTo({ screen: tab })
 *   - "Exit Editor" returns to viewer mode (auto-navigates to library)
 *
 * The Editor/Profiles/Settings screens render here as pure content —
 * they no longer ship their own top bars.
 */

type EditorTab = Extract<NavScreen, 'editor' | 'profiles' | 'settings'>

const TABS: { id: EditorTab; label: string; icon: ReactNode }[] = [
  {
    id: 'editor',
    label: 'Channels',
    icon: (
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
        <rect x="2" y="3" width="10" height="8" rx="1.5" stroke="currentColor" strokeWidth="1.4" fill="none" />
        <path d="M6 5.5L9 7L6 8.5V5.5Z" fill="currentColor" />
      </svg>
    ),
  },
  {
    id: 'profiles',
    label: 'Profiles',
    icon: (
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
        <circle cx="7" cy="5" r="2.3" stroke="currentColor" strokeWidth="1.4" fill="none" />
        <path d="M2 11.5C2 9.5 4.5 8.5 7 8.5C9.5 8.5 12 9.5 12 11.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" fill="none" />
      </svg>
    ),
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: (
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
        <circle cx="7" cy="7" r="2.2" stroke="currentColor" strokeWidth="1.4" fill="none" />
        <path d="M7 0.8v1.6M7 11.6v1.6M13.2 7h-1.6M2.4 7H0.8M11.38 2.62l-1.13 1.13M3.75 10.25l-1.13 1.13M11.38 11.38l-1.13-1.13M3.75 3.75l-1.13-1.13" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
      </svg>
    ),
  },
]

function formatTimer(seconds: number): string {
  if (seconds <= 0) return '0:00'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}

export default function EditorShell({
  activeTab,
  children,
}: {
  activeTab: EditorTab
  children: ReactNode
}) {
  const { state, navigateTo, send } = useAppStore()
  const { editorRemainingSeconds, activeDownload } = state

  const handleExit = () => {
    send({ type: 'exitEditorMode' })
    // The mode flip is auto-navigated to library by AppContent's effect.
  }

  const isUrgent = editorRemainingSeconds > 0 && editorRemainingSeconds <= 60

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--bg)',
    }}>
      {/* Unified top bar */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        padding: '0 18px',
        height: 56,
        borderBottom: '1px solid var(--border)',
        background: 'rgba(13,13,15,0.95)',
        backdropFilter: 'blur(12px)',
        WebkitBackdropFilter: 'blur(12px)',
        flexShrink: 0,
      }}>
        {/* Editor badge — anchor the user in the parent surface */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 22,
            height: 22,
            borderRadius: 6,
            background: 'var(--accent-dim)',
            border: '1px solid rgba(155,93,229,0.3)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
              <path d="M9.5 1.5L10.5 2.5L3.5 9.5H2.5V8.5L9.5 1.5Z" stroke="var(--accent)" strokeWidth="1.3" strokeLinejoin="round" fill="none" />
            </svg>
          </div>
          <span style={{ fontSize: 14, fontWeight: 700, letterSpacing: '-0.01em', color: 'var(--accent)' }}>
            Editor
          </span>
        </div>

        <div style={{ width: 1, height: 18, background: 'var(--border)' }} />

        {/* Tabs — the canonical navigation between editor sub-surfaces */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          {TABS.map(t => (
            <TabPill
              key={t.id}
              active={t.id === activeTab}
              icon={t.icon}
              label={t.label}
              onClick={() => navigateTo({ screen: t.id })}
            />
          ))}
        </div>

        {/* Active download chip — keeps parents aware while editing */}
        {activeDownload && (
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '4px 10px',
            borderRadius: 99,
            background: 'var(--surface-el)',
            border: '1px solid var(--border)',
            marginLeft: 4,
          }}>
            <svg className="spinner" width="11" height="11" viewBox="0 0 11 11" fill="none">
              <circle cx="5.5" cy="5.5" r="4" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
              <path d="M5.5 1.5A4 4 0 0 1 9.5 5.5" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span style={{ fontSize: 11, color: 'var(--text-secondary)' }}>
              {Math.round(activeDownload.progress * 100)}%
            </span>
          </div>
        )}

        <div style={{ flex: 1 }} />

        {/* Auto-lock countdown */}
        {editorRemainingSeconds > 0 && (
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '5px 10px',
            borderRadius: 8,
            background: isUrgent ? 'rgba(248,113,113,0.10)' : 'var(--surface-el)',
            border: `1px solid ${isUrgent ? 'rgba(248,113,113,0.30)' : 'var(--border)'}`,
            transition: 'background 200ms ease, border-color 200ms ease',
          }}>
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <circle cx="6" cy="6.5" r="4.5" stroke={isUrgent ? '#f87171' : 'var(--text-tertiary)'} strokeWidth="1.3" fill="none" />
              <path d="M6 4V6.5L7.5 8" stroke={isUrgent ? '#f87171' : 'var(--text-tertiary)'} strokeWidth="1.3" strokeLinecap="round" />
              <path d="M4.5 1.5H7.5" stroke={isUrgent ? '#f87171' : 'var(--text-tertiary)'} strokeWidth="1.3" strokeLinecap="round" />
            </svg>
            <span style={{
              fontSize: 12,
              fontWeight: 600,
              fontFamily: 'ui-monospace, monospace',
              color: isUrgent ? 'var(--destructive)' : 'var(--text-secondary)',
            }}>
              {formatTimer(editorRemainingSeconds)}
            </span>
          </div>
        )}

        {/* Exit Editor — the only way out, always visible */}
        <ExitButton onClick={handleExit} />
      </div>

      {/* Tab content */}
      <div style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
        {children}
      </div>
    </div>
  )
}

function TabPill({
  active,
  icon,
  label,
  onClick,
}: {
  active: boolean
  icon: ReactNode
  label: string
  onClick: () => void
}) {
  const [hovered, setHovered] = useState(false)
  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 7,
        height: 32,
        padding: '0 12px',
        borderRadius: 8,
        border: '1px solid transparent',
        background: active
          ? 'var(--accent-dim)'
          : hovered
            ? 'rgba(255,255,255,0.06)'
            : 'transparent',
        borderColor: active ? 'rgba(155,93,229,0.32)' : 'transparent',
        color: active
          ? 'var(--accent)'
          : hovered
            ? 'var(--text-primary)'
            : 'var(--text-secondary)',
        fontSize: 13,
        fontWeight: 600,
        cursor: 'pointer',
        outline: 'none',
        transition: 'background 160ms ease, border-color 160ms ease, color 160ms ease',
      }}
    >
      <span style={{ display: 'flex' }}>{icon}</span>
      <span>{label}</span>
    </button>
  )
}

function ExitButton({ onClick }: { onClick: () => void }) {
  const [hovered, setHovered] = useState(false)
  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      title="Exit Editor"
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 6,
        height: 32,
        padding: '0 12px',
        borderRadius: 8,
        background: hovered ? 'rgba(248,113,113,0.14)' : 'rgba(248,113,113,0.06)',
        border: `1px solid ${hovered ? 'rgba(248,113,113,0.40)' : 'rgba(248,113,113,0.22)'}`,
        color: hovered ? '#fca5a5' : '#f87171cc',
        fontSize: 13,
        fontWeight: 600,
        cursor: 'pointer',
        outline: 'none',
        transition: 'background 160ms ease, border-color 160ms ease, color 160ms ease',
      }}
    >
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
        <path d="M8 1.5H12V12.5H8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
        <path d="M9 7H2M2 7L4 5M2 7L4 9" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      Exit Editor
    </button>
  )
}
