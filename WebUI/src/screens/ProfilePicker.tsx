import { useState } from 'react'
import { useAppStore } from '../store'
import type { Profile } from '../types'
import ProfileAvatar from '../components/ProfileAvatar'

/**
 * "Who's watching?" full-screen picker. Shown in viewer mode when at
 * least one profile exists and none is active. Also reachable from the
 * library via the profile chip.
 *
 * The two parent-only entry points — Editor and Settings — live up here
 * (top-right) instead of cluttering the in-profile library top bar.
 * Both are gated by the PIN: clicking either sends requestEditorMode,
 * and the post-validation callback either lets the editor screen open
 * (default route in editor mode) or navigates to Settings.
 */
export default function ProfilePicker() {
  const { state, send, navigateTo, setOnPINValidated } = useAppStore()
  const { profiles } = state
  const sortedProfiles = [...profiles].sort((a, b) => a.sortOrder - b.sortOrder)

  const pick = (profileId: string) => {
    send({ type: 'setActiveProfile', payload: { profileId } })
  }

  const openEditor = () => {
    // PIN intent = enter editor mode → default route is the editor screen
    setOnPINValidated((valid) => {
      setOnPINValidated(undefined)
      if (valid) navigateTo({ screen: 'editor' })
    })
    send({ type: 'requestEditorMode' })
  }

  const openSettings = () => {
    // PIN intent = enter editor mode, then route to settings
    setOnPINValidated((valid) => {
      setOnPINValidated(undefined)
      if (valid) navigateTo({ screen: 'settings' })
    })
    send({ type: 'requestEditorMode' })
  }

  return (
    <div role="dialog" aria-modal="true" aria-label="Pick a profile" style={{
      position: 'fixed',
      inset: 0,
      zIndex: 100,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'var(--bg)',
      padding: 40,
      gap: 56,
    }}>
      {/* Parent controls — top-right corner */}
      <div style={{
        position: 'absolute',
        top: 28,
        right: 32,
        display: 'flex',
        alignItems: 'center',
        gap: 8,
      }}>
        <PickerCornerButton
          label="Editor"
          onClick={openEditor}
          icon={(
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M11.5 2L14 4.5L5.5 13H3v-2.5L11.5 2z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" fill="none" />
            </svg>
          )}
        />
        <PickerCornerButton
          label="Settings"
          onClick={openSettings}
          icon={(
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <circle cx="9" cy="9" r="2.6" stroke="currentColor" strokeWidth="1.6" />
              <path d="M9 1.5V3M9 15V16.5M16.5 9H15M3 9H1.5M14.48 3.52l-1.06 1.06M4.58 13.42l-1.06 1.06M14.48 14.48l-1.06-1.06M4.58 4.58l-1.06-1.06" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
            </svg>
          )}
        />
      </div>

      <div style={{ textAlign: 'center', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <h1 style={{
          fontSize: 48,
          fontWeight: 800,
          letterSpacing: '-0.02em',
          color: 'var(--text-primary)',
        }}>
          Who's watching?
        </h1>
        <p style={{ fontSize: 20, color: 'var(--text-secondary)' }}>
          Pick a profile to start
        </p>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${Math.min(sortedProfiles.length, 4)}, minmax(180px, 1fr))`,
        gap: 36,
        maxWidth: 1000,
      }}>
        {sortedProfiles.map(p => (
          <ProfileTile key={p.id} profile={p} onPick={() => pick(p.id)} />
        ))}
      </div>
    </div>
  )
}

function ProfileTile({ profile, onPick }: { profile: Profile; onPick: () => void }) {
  const [hovered, setHovered] = useState(false)
  return (
    <button
      type="button"
      onClick={onPick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 18,
        padding: 18,
        background: 'transparent',
        border: 'none',
        cursor: 'pointer',
        outline: 'none',
        transform: hovered ? 'translateY(-4px)' : 'translateY(0)',
        transition: 'transform 220ms cubic-bezier(0.25, 1, 0.5, 1)',
      }}
    >
      <div style={{
        transform: hovered ? 'scale(1.06)' : 'scale(1)',
        transition: 'transform 240ms cubic-bezier(0.25, 1, 0.5, 1), filter 240ms ease',
        filter: hovered ? 'brightness(1.08)' : 'brightness(1)',
      }}>
        <ProfileAvatar profile={profile} size={172} />
      </div>
      <div style={{
        fontSize: 22,
        fontWeight: 700,
        color: hovered ? 'var(--text-primary)' : 'rgba(240,240,244,0.78)',
        letterSpacing: '-0.01em',
        transition: 'color 240ms ease',
      }}>
        {profile.name}
      </div>
    </button>
  )
}

function PickerCornerButton({
  label,
  icon,
  onClick,
}: {
  label: string
  icon: React.ReactNode
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
        gap: 8,
        padding: '8px 14px',
        borderRadius: 99,
        background: hovered ? 'rgba(255,255,255,0.10)' : 'rgba(255,255,255,0.04)',
        border: `1px solid ${hovered ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.10)'}`,
        color: 'var(--text-secondary)',
        fontSize: 13,
        fontWeight: 600,
        cursor: 'pointer',
        outline: 'none',
        transition: 'background 160ms ease, border-color 160ms ease, color 160ms ease',
      }}
      title={label}
    >
      <span style={{ display: 'flex', color: hovered ? 'var(--text-primary)' : 'var(--text-secondary)' }}>
        {icon}
      </span>
      <span style={{ color: hovered ? 'var(--text-primary)' : 'var(--text-secondary)' }}>
        {label}
      </span>
    </button>
  )
}
