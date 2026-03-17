import type { CSSProperties } from 'react'
import { useAppStore } from '../store'
import ChannelCard from '../components/ChannelCard'

export default function Library() {
  const { state, navigateTo, send } = useAppStore()
  const { channels, videos, appMode, activeDownload } = state

  const sortedChannels = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)

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
      background: 'var(--bg)',
    }}>
      {/* Top bar */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        padding: '0 24px',
        height: 56,
        borderBottom: '1px solid var(--border)',
        background: 'rgba(13,13,15,0.9)',
        backdropFilter: 'blur(12px)',
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
            width: 28,
            height: 28,
            borderRadius: 8,
            background: 'linear-gradient(135deg, #9b5de5, #60a5fa)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}>
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <polygon points="6,4 13,8 6,12" fill="white" />
            </svg>
          </div>
          <span style={{
            fontSize: 16,
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
            <svg className="spinner" width="12" height="12" viewBox="0 0 12 12" fill="none">
              <circle cx="6" cy="6" r="4.5" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
              <path d="M6 1.5A4.5 4.5 0 0 1 10.5 6" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
              {activeDownload.title || 'Downloading...'} — {Math.round(activeDownload.progress * 100)}%
            </span>
          </div>
        )}

        <div style={{ flex: activeDownload ? 0 : 1 }} />

        {/* Right actions */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
        } as CSSProperties}>
          {/* Editor mode toggle */}
          <button
            onClick={handleEditorToggle}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              padding: '5px 12px',
              borderRadius: 8,
              border: '1px solid',
              borderColor: appMode === 'editor' ? 'rgba(155,93,229,0.5)' : 'var(--border)',
              background: appMode === 'editor' ? 'rgba(155,93,229,0.15)' : 'transparent',
              color: appMode === 'editor' ? 'var(--accent)' : 'var(--text-secondary)',
              fontSize: 12,
              fontWeight: 600,
              cursor: 'pointer',
              transition: 'all 0.15s ease',
              letterSpacing: '0.02em',
              textTransform: 'uppercase',
            }}
          >
            <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
              {appMode === 'editor' ? (
                // Unlock icon
                <>
                  <rect x="2" y="6" width="9" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.5" fill="none" />
                  <path d="M4.5 6V4C4.5 2.62 5.62 1.5 7 1.5C8.38 1.5 9.5 2.62 9.5 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
                </>
              ) : (
                // Lock icon
                <>
                  <rect x="2" y="6" width="9" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.5" fill="none" />
                  <path d="M4 6V4.5C4 3 5 1.5 6.5 1.5C8 1.5 9 3 9 4.5V6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
                </>
              )}
            </svg>
            {appMode === 'editor' ? 'Editor' : 'Editor'}
          </button>

          {/* Settings */}
          <button
            className="lt-btn-ghost"
            onClick={() => navigateTo({ screen: 'settings' })}
            style={{
              padding: '6px 8px',
              borderRadius: 8,
              color: 'var(--text-secondary)',
            }}
            title="Settings"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <circle cx="9" cy="9" r="2.5" stroke="currentColor" strokeWidth="1.5" />
              <path d="M9 1.5V3M9 15V16.5M16.5 9H15M3 9H1.5M14.48 3.52l-1.06 1.06M4.58 13.42l-1.06 1.06M14.48 14.48l-1.06-1.06M4.58 4.58l-1.06-1.06" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          </button>

          {/* Go to Editor screen */}
          {appMode === 'editor' && (
            <button
              className="lt-btn-primary"
              onClick={() => navigateTo({ screen: 'editor' })}
              style={{ padding: '6px 12px', fontSize: 12, gap: 4 }}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M9.5 1.5L11.5 3.5L4.5 10.5H2.5V8.5L9.5 1.5Z" stroke="white" strokeWidth="1.4" strokeLinejoin="round" fill="none" />
              </svg>
              Manage
            </button>
          )}
        </div>
      </div>

      {/* Content */}
      <div style={{
        flex: 1,
        overflowY: 'auto',
        padding: '24px',
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
              width: 80,
              height: 80,
              borderRadius: 24,
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: 8,
            }}>
              <svg width="36" height="36" viewBox="0 0 36 36" fill="none">
                <rect x="3" y="7" width="30" height="22" rx="4" stroke="var(--text-tertiary)" strokeWidth="2" fill="none" />
                <polygon points="14,13 26,18 14,23" fill="var(--text-tertiary)" />
              </svg>
            </div>
            <h2 style={{ fontSize: 20, color: 'var(--text-primary)' }}>
              No channels yet
            </h2>
            <p style={{
              color: 'var(--text-secondary)',
              fontSize: 14,
              textAlign: 'center',
              maxWidth: 280,
            }}>
              {appMode === 'editor'
                ? 'Head to the Editor to create channels and add videos.'
                : 'Ask your admin to add channels in Editor mode.'}
            </p>
            {appMode === 'editor' && (
              <button
                className="lt-btn-primary"
                onClick={() => navigateTo({ screen: 'editor' })}
                style={{ marginTop: 8 }}
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
              marginBottom: 16,
            }}>
              <h2 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)' }}>
                Channels
              </h2>
              <span style={{ fontSize: 13, color: 'var(--text-tertiary)' }}>
                {sortedChannels.length} {sortedChannels.length === 1 ? 'channel' : 'channels'}
              </span>
            </div>

            {/* Grid */}
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))',
              gap: 16,
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
