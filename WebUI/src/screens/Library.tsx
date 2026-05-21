import { useMemo, useState, type CSSProperties, type ReactNode } from 'react'
import { useAppStore } from '../store'
import ChannelCard from '../components/ChannelCard'
import ProfileAvatar from '../components/ProfileAvatar'
import AmbientBackground from '../components/AmbientBackground'
import type { Profile } from '../types'

export default function Library() {
  const { state, navigateTo, send } = useAppStore()
  const { channels, videos, appMode, activeDownload, profiles, profileChannels, activeProfileId } = state

  // Editor mode sees every channel; viewer mode filters to the active
  // profile's assigned channels. If there's no active profile (or no
  // profiles at all), the viewer also sees every channel — clean fallback
  // for installs that haven't set profiles up.
  const visibleChannels = (() => {
    if (appMode === 'editor') return channels
    if (!activeProfileId) return channels
    const assigned = new Set(profileChannels[activeProfileId] ?? [])
    return channels.filter(c => assigned.has(c.id))
  })()
  const sortedChannels = [...visibleChannels].sort((a, b) => a.sortOrder - b.sortOrder)
  const activeProfile = profiles.find(p => p.id === activeProfileId) ?? null

  // Ambient background sources: every visible channel's banner. Each
  // banner cycles in for ~9s with a soft crossfade — same blur stack as
  // the channel page. If no banners exist yet we fall back to first
  // video thumbnails so the bg still has something to chew on.
  const ambientSources = useMemo(() => {
    const fromBanners = sortedChannels
      .map(c => c.bannerPath)
      .filter((b): b is string => !!b)
    if (fromBanners.length > 0) return fromBanners
    // Fallback: first ready thumbnail per channel
    const fromThumbs: string[] = []
    for (const c of sortedChannels) {
      const list = videos[c.id] ?? []
      const v = list.find(x => x.downloadState === 'ready' && x.thumbnailPath)
      if (v?.thumbnailPath) fromThumbs.push(v.thumbnailPath)
    }
    return fromThumbs
  }, [sortedChannels, videos])

  const handleChannelClick = (channelId: string) => {
    navigateTo({ screen: 'channel', channelId })
  }

  const handleEditorToggle = () => {
    if (appMode === 'editor') {
      send({ type: 'exitEditorMode' })
    } else {
      send({ type: 'requestEditorMode' })
    }
  }

  return (
    <div className="screen-enter" style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      position: 'relative',
      overflow: 'hidden',
      background: 'var(--bg)',
    }}>
      {/* Ambient background — cycles through channel banners */}
      <AmbientBackground sources={ambientSources} />

      {/* Top bar */}
      <div style={{
        position: 'relative',
        zIndex: 1,
        display: 'flex',
        alignItems: 'center',
        padding: '0 40px',
        height: 80,
        background: 'linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.04) 100%)',
        backgroundColor: 'rgba(13,13,15,0.82)',
        backdropFilter: 'blur(24px) saturate(180%)',
        WebkitBackdropFilter: 'blur(24px) saturate(180%)',
        borderBottom: '0.5px solid rgba(255,255,255,0.1)',
        flexShrink: 0,
        gap: 12,
      } as CSSProperties}>
        {/* Logo + title */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 9,
        } as CSSProperties}>
          <div style={{
            width: 44,
            height: 44,
            borderRadius: 12,
            background: 'linear-gradient(135deg, #9b5de5, #60a5fa)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}>
            <svg width="24" height="24" viewBox="0 0 16 16" fill="none">
              <polygon points="6,4 13,8 6,12" fill="white" />
            </svg>
          </div>
          <span style={{
            fontSize: 28,
            fontWeight: 700,
            letterSpacing: '-0.02em',
            color: 'var(--text-primary)',
          }}>
            LocalTube
          </span>
        </div>

        {/* Active download indicator */}
        {activeDownload && (
          <div style={{
            flex: 1,
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            justifyContent: 'center',
          }}>
            <svg className="spinner" width="16" height="16" viewBox="0 0 12 12" fill="none">
              <circle cx="6" cy="6" r="4.5" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
              <path d="M6 1.5A4.5 4.5 0 0 1 10.5 6" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span style={{ fontSize: 16, color: 'var(--text-secondary)' }}>
              {activeDownload.title || 'Downloading...'} — {Math.round(activeDownload.progress * 100)}%
            </span>
          </div>
        )}

        <div style={{ flex: activeDownload ? 0 : 1 }} />

        {/* Right actions — Library is viewer-only now. Entering editor
            mode auto-navigates to EditorShell (handled in App.tsx).
              - With profiles: profile chip (click → back to picker)
              - Without profiles: one Editor entry so the parent can
                still get in on a fresh install. */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
        } as CSSProperties}>
          {activeProfile ? (
            <ProfileChip profile={activeProfile} onClick={() =>
              send({ type: 'setActiveProfile', payload: { profileId: null } })
            } />
          ) : (
            <TopBarButton
              kind="secondary"
              onClick={handleEditorToggle}
              label="Editor"
              icon={(
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M10 1.5L12.5 4L4.5 12H2V9.5L10 1.5Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" fill="none" />
                </svg>
              )}
            />
          )}
        </div>
      </div>

      {/* Content */}
      <div style={{
        position: 'relative',
        zIndex: 1,
        flex: 1,
        overflowY: 'auto',
        padding: '44px',
      }}>
        {sortedChannels.length === 0 ? (
          // Empty state
          <div style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            height: '100%',
            gap: 16,
          }}>
            <div style={{
              width: 120,
              height: 120,
              borderRadius: 36,
              background: 'linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.04) 100%)',
              backdropFilter: 'blur(20px) saturate(180%)',
              WebkitBackdropFilter: 'blur(20px) saturate(180%)',
              border: '0.5px solid rgba(255,255,255,0.13)',
              boxShadow: '0 8px 32px rgba(0,0,0,0.4), inset 0 0 0 1px rgba(255,255,255,0.06)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: 8,
            }}>
              <svg width="56" height="56" viewBox="0 0 36 36" fill="none">
                <rect x="3" y="7" width="30" height="22" rx="4" stroke="var(--text-tertiary)" strokeWidth="2" fill="none" />
                <polygon points="14,13 26,18 14,23" fill="var(--text-tertiary)" />
              </svg>
            </div>
            <h2 style={{ fontSize: 36, color: 'var(--text-primary)' }}>
              No channels yet
            </h2>
            <p style={{
              color: 'var(--text-secondary)',
              fontSize: 20,
              textAlign: 'center',
              maxWidth: 380,
            }}>
              {appMode === 'editor'
                ? 'Head to the Editor to create channels and add videos.'
                : 'Ask your admin to add channels in Editor mode.'}
            </p>
            {appMode === 'editor' && (
              <button
                className="lt-btn-primary"
                onClick={() => navigateTo({ screen: 'editor' })}
                style={{ marginTop: 16 }}
              >
                Open Editor
              </button>
            )}
          </div>
        ) : (
          <>
            {/* Section header */}
            <div style={{
              display: 'flex',
              alignItems: 'baseline',
              justifyContent: 'space-between',
              marginBottom: 28,
            }}>
              <h2 style={{ fontSize: 36, fontWeight: 800, color: 'var(--text-primary)' }}>
                Channels
              </h2>
              <span style={{ fontSize: 18, color: 'var(--text-tertiary)' }}>
                {sortedChannels.length} {sortedChannels.length === 1 ? 'channel' : 'channels'}
              </span>
            </div>

            {/* Grid */}
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))',
              gap: 24,
            }}>
              {sortedChannels.map(channel => {
                const channelVideos = videos[channel.id] ?? []
                const isDownloading = channelVideos.some(
                  v => v.downloadState === 'downloading' || v.downloadState === 'queued'
                )
                const downloadingVideo = channelVideos.find(
                  v => v.downloadState === 'downloading'
                )
                return (
                  <ChannelCard
                    key={channel.id}
                    channel={channel}
                    videos={channelVideos}
                    isDownloading={isDownloading}
                    downloadProgress={downloadingVideo?.downloadProgress}
                    onClick={() => handleChannelClick(channel.id)}
                  />
                )
              })}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

// ─── Shared top-bar button ────────────────────────────────────────────────────
// One canonical shell for every action in the library top bar. Same height,
// same padding, same icon/label spacing — three visual kinds that map to the
// hierarchy: primary (filled accent) → secondary (subtle surface) → exit
// (subtle destructive tint). Animations are CSS-easy: 160ms color/bg ease.

type TopBarButtonKind = 'primary' | 'secondary' | 'exit'

function TopBarButton({
  kind,
  label,
  icon,
  onClick,
}: {
  kind: TopBarButtonKind
  label: string
  icon: ReactNode
  onClick: () => void
}) {
  const [hovered, setHovered] = useState(false)

  const palette = (() => {
    switch (kind) {
      case 'primary':
        return {
          bg:       hovered ? 'var(--accent-hover, #ad6df0)' : 'var(--accent)',
          border:   'transparent',
          color:    'white',
        }
      case 'secondary':
        return {
          bg:       hovered ? 'rgba(255,255,255,0.10)' : 'rgba(255,255,255,0.04)',
          border:   hovered ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.10)',
          color:    hovered ? 'var(--text-primary)'   : 'var(--text-secondary)',
        }
      case 'exit':
        return {
          bg:       hovered ? 'rgba(248,113,113,0.14)' : 'rgba(248,113,113,0.06)',
          border:   hovered ? 'rgba(248,113,113,0.40)' : 'rgba(248,113,113,0.22)',
          color:    hovered ? '#fca5a5'                : '#f87171cc',
        }
    }
  })()

  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 6,
        height: 34,
        padding: '0 14px',
        borderRadius: 10,
        background: palette.bg,
        border: `1px solid ${palette.border}`,
        color: palette.color,
        fontSize: 13,
        fontWeight: 600,
        letterSpacing: '-0.005em',
        cursor: 'pointer',
        outline: 'none',
        transition: 'background 160ms ease, border-color 160ms ease, color 160ms ease',
      }}
    >
      <span style={{ display: 'flex', alignItems: 'center' }}>{icon}</span>
      <span>{label}</span>
    </button>
  )
}

// ─── Profile chip (viewer mode only) ──────────────────────────────────────────
// Compact circle — just the avatar, name shown only on hover via title.
// Profile identity is already established by the picker; in-app the user
// only needs to *recognise* their profile, not re-read their name.
function ProfileChip({ profile, onClick }: { profile: Profile; onClick: () => void }) {
  const [hovered, setHovered] = useState(false)
  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      title={`${profile.name} — switch profile`}
      aria-label={`Switch profile (currently ${profile.name})`}
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: 44,
        height: 44,
        padding: 0,
        borderRadius: '50%',
        background: hovered ? 'rgba(255,255,255,0.10)' : 'transparent',
        border: `1px solid ${hovered ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.10)'}`,
        cursor: 'pointer',
        transition: 'background 160ms ease, border-color 160ms ease, transform 200ms cubic-bezier(0.25,1,0.5,1)',
        transform: hovered ? 'scale(1.05)' : 'scale(1)',
      }}
    >
      <ProfileAvatar profile={profile} size={36} />
    </button>
  )
}
