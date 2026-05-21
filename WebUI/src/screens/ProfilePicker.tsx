import { useAppStore } from '../store'
import type { Profile } from '../types'

/**
 * "Who's watching?" full-screen picker. Shown when at least one profile
 * exists and none is active yet, and reachable from the library via the
 * profile chip in the top bar. Picking a profile dispatches
 * setActiveProfile to Swift, which persists the choice and emits
 * activeProfileChanged — the reducer flips activeProfileId and the
 * library re-filters to that profile's channels.
 */
export default function ProfilePicker() {
  const { state, send } = useAppStore()
  const { profiles } = state
  const sortedProfiles = [...profiles].sort((a, b) => a.sortOrder - b.sortOrder)

  const pick = (profileId: string) => {
    send({ type: 'setActiveProfile', payload: { profileId } })
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
      gap: 48,
    }}>
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
        gap: 32,
        maxWidth: 960,
      }}>
        {sortedProfiles.map(p => (
          <ProfileTile key={p.id} profile={p} onPick={() => pick(p.id)} />
        ))}
      </div>
    </div>
  )
}

function ProfileTile({ profile, onPick }: { profile: Profile; onPick: () => void }) {
  return (
    <button
      onClick={onPick}
      className="lt-profile-tile"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 16,
        padding: 24,
        background: 'transparent',
        border: 'none',
        cursor: 'pointer',
      }}
    >
      <div style={{
        width: 160,
        height: 160,
        borderRadius: 32,
        background: 'linear-gradient(135deg, rgba(155,93,229,0.25) 0%, rgba(96,165,250,0.18) 100%)',
        border: '2px solid rgba(255,255,255,0.13)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 84,
        transition: 'transform 200ms cubic-bezier(0.25,1,0.5,1), border-color 200ms ease, box-shadow 200ms ease',
        boxShadow: '0 8px 32px rgba(0,0,0,0.35)',
      }}>
        <span>{profile.emoji || '🙂'}</span>
      </div>
      <div style={{
        fontSize: 22,
        fontWeight: 700,
        color: 'var(--text-primary)',
        letterSpacing: '-0.01em',
      }}>
        {profile.name}
      </div>
    </button>
  )
}
