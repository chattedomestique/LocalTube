import { useState } from 'react'
import { useAppStore } from '../store'
import VideoCard from '../components/VideoCard'
import type { Video } from '../types'

export default function Channel() {
  const { state, nav, navigateTo, send } = useAppStore()
  const { channels, videos, appMode, activeDownload } = state
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [showAddVideos, setShowAddVideos] = useState(false)
  const [urlInput, setUrlInput] = useState('')
  const [adding, setAdding] = useState(false)

  const channel = channels.find(c => c.id === nav.channelId)
  const channelVideos = (nav.channelId ? videos[nav.channelId] : []) ?? []
  const sortedVideos = [...channelVideos].sort((a, b) => a.sortOrder - b.sortOrder)
  const isEditor = appMode === 'editor'

  if (!channel) {
    return (
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        height: '100%',
        gap: 12,
      }}>
        <p style={{ color: 'var(--text-secondary)' }}>Channel not found.</p>
        <button className="lt-btn-secondary" onClick={() => navigateTo({ screen: 'library' })}>
          ← Back to Library
        </button>
      </div>
    )
  }

  const handleDeleteChannel = () => {
    send({ type: 'deleteChannel', payload: { channelId: channel.id } })
    navigateTo({ screen: 'library' })
  }

  const handleAddVideos = () => {
    const urls = urlInput
      .split('\n')
      .map(u => u.trim())
      .filter(u => u.length > 0)
    if (urls.length === 0) return
    setAdding(true)
    send({ type: 'addVideoURLs', payload: { channelId: channel.id, urls } })
    setUrlInput('')
    setAdding(false)
    setShowAddVideos(false)
  }

  const handleDeleteVideo = (videoId: string) => {
    send({ type: 'deleteVideo', payload: { videoId } })
  }

  const handleRetry = (videoId: string) => {
    send({ type: 'retryDownload', payload: { videoId } })
  }

  const readyCount = sortedVideos.filter(v => v.downloadState === 'ready').length

  return (
    <div className="screen-slide-in" style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--bg)',
    }}>
      {/* Top bar */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        padding: '0 20px',
        height: 56,
        borderBottom: '1px solid var(--border)',
        background: 'rgba(13,13,15,0.9)',
        backdropFilter: 'blur(12px)',
        flexShrink: 0,
        gap: 12,
      }}>
        {/* Back button */}
        <button
          className="lt-btn-ghost"
          onClick={() => navigateTo({ screen: 'library' })}
          style={{ padding: '6px 10px', gap: 4, color: 'var(--text-secondary)' }}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M10 3L5 8L10 13" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Library
        </button>

        <div style={{ width: 1, height: 18, background: 'var(--border)' }} />

        {/* Channel name */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1 }}>
          {channel.emoji && (
            <span style={{ fontSize: 20 }}>{channel.emoji}</span>
          )}
          <div>
            <h1 style={{ fontSize: 16, fontWeight: 700, letterSpacing: '-0.02em' }}>
              {channel.displayName}
            </h1>
          </div>
          <div style={{
            padding: '2px 9px',
            borderRadius: 99,
            background: 'var(--surface-el)',
            border: '1px solid var(--border)',
            fontSize: 12,
            color: 'var(--text-secondary)',
            marginLeft: 4,
          }}>
            {readyCount}/{sortedVideos.length}
          </div>
        </div>

        {/* Right controls */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {/* Add videos (editor) */}
          {isEditor && (
            <button
              className="lt-btn-primary"
              onClick={() => setShowAddVideos(true)}
              style={{ padding: '6px 12px', fontSize: 12 }}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M6.5 2V11M2 6.5H11" stroke="white" strokeWidth="1.8" strokeLinecap="round" />
              </svg>
              Add Videos
            </button>
          )}

          {/* Delete channel (editor) */}
          {isEditor && (
            <button
              className="lt-btn-destructive"
              onClick={() => setShowDeleteConfirm(true)}
              style={{ padding: '6px 12px', fontSize: 12 }}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M2 3.5H11M4.5 3.5V2.5A1 1 0 0 1 5.5 1.5H7.5A1 1 0 0 1 8.5 2.5V3.5M5 6V10M8 6V10" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M3 3.5L3.5 11H9.5L10 3.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Delete
            </button>
          )}

          {/* View mode toggle */}
          <div style={{
            display: 'flex',
            background: 'var(--surface-el)',
            border: '1px solid var(--border)',
            borderRadius: 8,
            padding: 2,
          }}>
            {(['grid', 'list'] as const).map(mode => (
              <button
                key={mode}
                onClick={() => setViewMode(mode)}
                style={{
                  width: 28,
                  height: 26,
                  borderRadius: 6,
                  border: 'none',
                  background: viewMode === mode ? 'var(--surface)' : 'transparent',
                  color: viewMode === mode ? 'var(--text-primary)' : 'var(--text-tertiary)',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  transition: 'all 0.15s ease',
                }}
              >
                {mode === 'grid' ? (
                  <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                    <rect x="1" y="1" width="4.5" height="4.5" rx="1" fill="currentColor" opacity="0.8" />
                    <rect x="7.5" y="1" width="4.5" height="4.5" rx="1" fill="currentColor" opacity="0.8" />
                    <rect x="1" y="7.5" width="4.5" height="4.5" rx="1" fill="currentColor" opacity="0.8" />
                    <rect x="7.5" y="7.5" width="4.5" height="4.5" rx="1" fill="currentColor" opacity="0.8" />
                  </svg>
                ) : (
                  <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                    <path d="M1 3H12M1 6.5H12M1 10H12" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
                  </svg>
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Content */}
      <div style={{
        flex: 1,
        overflowY: 'auto',
        padding: '24px',
      }}>
        {sortedVideos.length === 0 ? (
          <div style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            height: '100%',
            gap: 12,
          }}>
            <div style={{
              width: 64,
              height: 64,
              borderRadius: 18,
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
                <rect x="2" y="4" width="24" height="20" rx="3.5" stroke="var(--text-tertiary)" strokeWidth="1.5" fill="none" />
                <polygon points="11,10 21,14 11,18" fill="var(--text-tertiary)" />
              </svg>
            </div>
            <h2 style={{ fontSize: 16 }}>No videos in {channel.displayName}</h2>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 260 }}>
              {isEditor
                ? 'Add YouTube video URLs to start downloading.'
                : 'Videos will appear here when they\'re added.'}
            </p>
            {isEditor && (
              <button
                className="lt-btn-primary"
                onClick={() => setShowAddVideos(true)}
                style={{ marginTop: 4 }}
              >
                Add Videos
              </button>
            )}
          </div>
        ) : viewMode === 'grid' ? (
          <div style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
            gap: 14,
          }}>
            {sortedVideos.map(video => (
              <VideoCard
                key={video.id}
                video={video}
                isEditorMode={isEditor}
                isActiveDownload={activeDownload?.videoId === video.id}
                onPlay={() => send({ type: 'playVideo', payload: { videoId: video.id } })}
                onDelete={isEditor ? () => handleDeleteVideo(video.id) : undefined}
                onRetry={() => handleRetry(video.id)}
              />
            ))}
          </div>
        ) : (
          // List view
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {sortedVideos.map(video => (
              <VideoListRow
                key={video.id}
                video={video}
                isEditorMode={isEditor}
                isActiveDownload={activeDownload?.videoId === video.id}
                onPlay={() => send({ type: 'playVideo', payload: { videoId: video.id } })}
                onDelete={isEditor ? () => handleDeleteVideo(video.id) : undefined}
                onRetry={() => handleRetry(video.id)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Delete channel confirm modal */}
      {showDeleteConfirm && (
        <div className="modal-backdrop">
          <div className="modal-panel" style={{ width: 360, padding: '32px 28px' }}>
            <div style={{
              width: 52,
              height: 52,
              borderRadius: 16,
              background: 'rgba(248,113,113,0.1)',
              border: '1px solid rgba(248,113,113,0.25)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: 16,
            }}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
                <path d="M3 6H21M8 6V4H16V6M10 11V17M14 11V17" stroke="#f87171" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M5 6L6 20H18L19 6" stroke="#f87171" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <h2 style={{ fontSize: 17, marginBottom: 8 }}>Delete "{channel.displayName}"?</h2>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 24 }}>
              This will remove the channel and all its videos from LocalTube. Downloaded files will also be deleted.
            </p>
            <div style={{ display: 'flex', gap: 10 }}>
              <button
                className="lt-btn-secondary"
                onClick={() => setShowDeleteConfirm(false)}
                style={{ flex: 1, justifyContent: 'center' }}
              >
                Cancel
              </button>
              <button
                className="lt-btn-destructive"
                onClick={handleDeleteChannel}
                style={{ flex: 1, justifyContent: 'center' }}
              >
                Delete Channel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Add videos modal */}
      {showAddVideos && (
        <div className="modal-backdrop">
          <div className="modal-panel" style={{ width: 480, padding: '28px' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
              <div>
                <h2 style={{ fontSize: 17, marginBottom: 4 }}>Add Videos</h2>
                <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
                  Paste YouTube URLs, one per line.
                </p>
              </div>
              <button
                className="lt-btn-ghost"
                onClick={() => { setShowAddVideos(false); setUrlInput('') }}
                style={{ padding: '6px 8px' }}
              >
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                  <path d="M3 3L13 13M13 3L3 13" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
                </svg>
              </button>
            </div>
            <textarea
              className="lt-input"
              value={urlInput}
              onChange={e => setUrlInput(e.target.value)}
              placeholder={"https://youtube.com/watch?v=...\nhttps://youtube.com/watch?v=..."}
              rows={8}
              style={{ fontFamily: 'ui-monospace, monospace', fontSize: 13 }}
            />
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 16 }}>
              <button
                className="lt-btn-secondary"
                onClick={() => { setShowAddVideos(false); setUrlInput('') }}
              >
                Cancel
              </button>
              <button
                className="lt-btn-primary"
                onClick={handleAddVideos}
                disabled={urlInput.trim().length === 0 || adding}
              >
                {adding ? 'Adding...' : `Queue Downloads`}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ─── List Row ─────────────────────────────────────────────────────────────────
function VideoListRow({
  video,
  isEditorMode,
  isActiveDownload,
  onPlay,
  onDelete,
  onRetry,
}: {
  video: Video
  isEditorMode: boolean
  isActiveDownload?: boolean
  onPlay: () => void
  onDelete?: () => void
  onRetry?: () => void
}) {
  const [hovered, setHovered] = useState(false)
  const isReady = video.downloadState === 'ready'
  const isDownloading = video.downloadState === 'downloading' || isActiveDownload
  const isQueued = video.downloadState === 'queued'
  const isError = video.downloadState === 'error'

  const duration = (() => {
    const s = video.durationSeconds
    if (!s) return ''
    const h = Math.floor(s / 3600)
    const m = Math.floor((s % 3600) / 60)
    const sec = s % 60
    if (h > 0) return `${h}:${m.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
    return `${m}:${sec.toString().padStart(2, '0')}`
  })()

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onClick={isReady ? onPlay : undefined}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        padding: '8px 12px',
        borderRadius: 10,
        background: hovered ? 'var(--surface)' : 'transparent',
        cursor: isReady ? 'pointer' : 'default',
        transition: 'background 0.1s ease',
      }}
    >
      {/* Thumbnail */}
      <div style={{
        width: 80,
        height: 45,
        borderRadius: 6,
        overflow: 'hidden',
        flexShrink: 0,
        background: 'var(--surface-el)',
        position: 'relative',
      }}>
        {video.thumbnailPath && (
          <img
            src={`localtube-thumb://${video.thumbnailPath}`}
            alt=""
            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
          />
        )}
        {duration && (
          <div style={{
            position: 'absolute',
            bottom: 2,
            right: 2,
            background: 'rgba(0,0,0,0.8)',
            borderRadius: 3,
            padding: '1px 4px',
            fontSize: 9,
            fontWeight: 700,
            color: 'white',
          }}>
            {duration}
          </div>
        )}
      </div>

      {/* Title */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{
          fontSize: 13,
          fontWeight: 500,
          color: isReady ? 'var(--text-primary)' : 'var(--text-secondary)',
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          letterSpacing: '-0.01em',
        }}>
          {video.title}
        </p>
      </div>

      {/* State */}
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 8 }}>
        {isDownloading && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            <svg className="spinner" width="12" height="12" viewBox="0 0 12 12" fill="none">
              <circle cx="6" cy="6" r="4.5" stroke="rgba(155,93,229,0.3)" strokeWidth="1.5" />
              <path d="M6 1.5A4.5 4.5 0 0 1 10.5 6" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span style={{ fontSize: 11, color: 'var(--accent)' }}>
              {Math.round(video.downloadProgress * 100)}%
            </span>
          </div>
        )}
        {isQueued && (
          <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>Queued</span>
        )}
        {isReady && (
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <circle cx="7" cy="7" r="5.5" fill="none" stroke="#34d399" strokeWidth="1.5" />
            <path d="M4.5 7L6.5 9L9.5 5" stroke="#34d399" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        )}
        {isError && (
          <button
            onClick={(e) => { e.stopPropagation(); onRetry?.() }}
            style={{
              fontSize: 11,
              color: 'var(--destructive)',
              background: 'rgba(248,113,113,0.1)',
              border: '1px solid rgba(248,113,113,0.25)',
              borderRadius: 5,
              padding: '2px 7px',
              cursor: 'pointer',
            }}
          >
            Retry
          </button>
        )}
        {isEditorMode && hovered && onDelete && (
          <button
            onClick={(e) => { e.stopPropagation(); onDelete() }}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 26,
              height: 26,
              borderRadius: 6,
              border: '1px solid rgba(248,113,113,0.3)',
              background: 'rgba(248,113,113,0.1)',
              color: 'var(--destructive)',
              cursor: 'pointer',
            }}
          >
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
              <path d="M2 2.5H9M3.5 2.5V2A1 1 0 0 1 4.5 1H6.5A1 1 0 0 1 7.5 2V2.5M4 4.5V8.5M7 4.5V8.5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
              <path d="M2.5 2.5L3 9.5H8L8.5 2.5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        )}
      </div>
    </div>
  )
}

