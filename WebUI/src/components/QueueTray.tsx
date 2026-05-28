import { useMemo, useState } from 'react'
import { useAppStore } from '../store'
import { Thumb } from './VideoCard'
import type { Video } from '../types'

/**
 * Slide-out queue tray (right edge). Shows the active profile's active
 * playlist.
 *
 * Permission model:
 *   - Viewer (kid): READ-ONLY. Tap a video to play it. No edit controls.
 *   - Edit layer (adult): drag-reorder, remove, clear.
 *
 * Rendered at the App level (viewer mode + active profile). Manages its
 * own open/closed state with a floating toggle handle on the right edge.
 */
const TRAY_WIDTH = 360

function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return ''
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  if (h > 0) return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  return `${m}:${s.toString().padStart(2, '0')}`
}

export default function QueueTray() {
  const { state, send } = useAppStore()
  const { activeProfileId, profiles, playlists, playlistVideos, videos, isEditing, nowPlayingVideoId } = state

  const [open, setOpen] = useState(false)
  const [showClearConfirm, setShowClearConfirm] = useState(false)
  const [draggingId, setDraggingId] = useState<string | null>(null)
  const [overId, setOverId] = useState<string | null>(null)

  const profile = profiles.find(p => p.id === activeProfileId) ?? null
  const activePlaylist = playlists.find(p => p.id === profile?.activePlaylistId) ?? null

  // Resolve the ordered video ids into video objects (skipping any that
  // no longer exist, e.g. deleted since being queued).
  const videoById = useMemo(() => {
    const m = new Map<string, Video>()
    for (const list of Object.values(videos)) {
      for (const v of list) m.set(v.id, v)
    }
    return m
  }, [videos])

  const queueIds = activePlaylist ? (playlistVideos[activePlaylist.id] ?? []) : []
  const queueVideos = queueIds
    .map(id => videoById.get(id))
    .filter((v): v is Video => v !== undefined)

  if (!profile || !activePlaylist) return null

  const canEdit = isEditing
  const count = queueVideos.length

  // ── Edit-layer mutations ──────────────────────────────────────────────
  const removeVideo = (videoId: string) => {
    send({ type: 'removeFromPlaylist', payload: { playlistId: activePlaylist.id, videoId } })
  }
  const clearQueue = () => {
    send({ type: 'clearPlaylist', payload: { playlistId: activePlaylist.id } })
    setShowClearConfirm(false)
  }
  const onDragStart = (id: string) => (e: React.DragEvent) => {
    if (!canEdit) return
    setDraggingId(id)
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', id)
  }
  const onDragOver = (id: string) => (e: React.DragEvent) => {
    if (!canEdit || !draggingId || id === draggingId) return
    e.preventDefault()
    if (overId !== id) setOverId(id)
  }
  const onDrop = (targetId: string) => (e: React.DragEvent) => {
    if (!canEdit || !draggingId) return
    e.preventDefault()
    const without = queueIds.filter(x => x !== draggingId)
    const targetIdx = without.indexOf(targetId)
    if (targetIdx === -1) return
    const newOrder = [...without.slice(0, targetIdx), draggingId, ...without.slice(targetIdx)]
    send({ type: 'reorderPlaylist', payload: { playlistId: activePlaylist.id, videoIds: newOrder } })
    setDraggingId(null); setOverId(null)
  }

  return (
    <>
      {/* Floating toggle — right edge, vertically centered. Hidden while
          the tray is open (the tray has its own close button). */}
      {!open && (
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label={`Open queue (${count} videos)`}
          title="Up Next"
          style={{
            position: 'fixed',
            right: 0,
            top: '50%',
            transform: 'translateY(-50%)',
            zIndex: 60,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: 6,
            padding: '14px 12px',
            borderRadius: '14px 0 0 14px',
            background: 'rgba(20,20,25,0.88)',
            backdropFilter: 'blur(20px) saturate(180%)',
            WebkitBackdropFilter: 'blur(20px) saturate(180%)',
            border: '1px solid rgba(255,255,255,0.14)',
            borderRight: 'none',
            color: 'var(--text-primary)',
            cursor: 'pointer',
            boxShadow: '-6px 0 20px rgba(0,0,0,0.35)',
          }}
        >
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
            <path d="M3 5h11M3 10h11M3 15h7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            <path d="M16 12v6M19 15h-6" stroke="var(--accent)" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
          {count > 0 && (
            <span style={{
              fontSize: 12,
              fontWeight: 700,
              minWidth: 20,
              height: 20,
              borderRadius: 10,
              background: 'var(--accent)',
              color: 'white',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '0 6px',
            }}>
              {count}
            </span>
          )}
        </button>
      )}

      {/* Backdrop (click to close) */}
      <div
        onClick={() => setOpen(false)}
        style={{
          position: 'fixed',
          inset: 0,
          zIndex: 70,
          background: 'rgba(0,0,0,0.35)',
          opacity: open ? 1 : 0,
          pointerEvents: open ? 'auto' : 'none',
          transition: 'opacity 240ms ease',
        }}
      />

      {/* Tray panel */}
      <div
        role="dialog"
        aria-label="Up Next queue"
        style={{
          position: 'fixed',
          top: 0,
          right: 0,
          bottom: 0,
          width: TRAY_WIDTH,
          zIndex: 71,
          display: 'flex',
          flexDirection: 'column',
          background: 'rgba(16,16,20,0.96)',
          backdropFilter: 'blur(28px) saturate(180%)',
          WebkitBackdropFilter: 'blur(28px) saturate(180%)',
          borderLeft: '1px solid rgba(255,255,255,0.12)',
          boxShadow: '-12px 0 40px rgba(0,0,0,0.5)',
          transform: open ? 'translateX(0)' : `translateX(${TRAY_WIDTH}px)`,
          transition: 'transform 280ms cubic-bezier(0.25, 1, 0.5, 1)',
        }}
      >
        {/* Header */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '16px 18px',
          borderBottom: '1px solid rgba(255,255,255,0.08)',
          flexShrink: 0,
        }}>
          <svg width="18" height="18" viewBox="0 0 20 20" fill="none">
            <path d="M3 5h11M3 10h11M3 15h7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            <path d="M16 12v6M19 15h-6" stroke="var(--accent)" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text-primary)' }}>
              {activePlaylist.name}
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
              {count} {count === 1 ? 'video' : 'videos'}
              {canEdit && ' · editing'}
            </div>
          </div>
          <button
            type="button"
            onClick={() => setOpen(false)}
            aria-label="Close queue"
            style={{
              width: 32, height: 32, borderRadius: 8,
              background: 'rgba(255,255,255,0.06)',
              border: '1px solid rgba(255,255,255,0.1)',
              color: 'var(--text-secondary)', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0,
            }}
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
              <path d="M3 3L11 11M11 3L3 11" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: 'auto', padding: 10 }}>
          {queueVideos.length === 0 ? (
            <div style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center',
              justifyContent: 'center', height: '100%', gap: 12, textAlign: 'center', padding: 24,
            }}>
              <span style={{ fontSize: 40 }}>🎬</span>
              <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                Your queue is empty.<br />
                {canEdit
                  ? 'Add videos with the + button on any video card.'
                  : 'Ask a grown-up to add some videos!'}
              </p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              {queueVideos.map((video, i) => {
                const isDragOver = canEdit && overId === video.id && draggingId !== video.id
                const isBeingDragged = canEdit && draggingId === video.id
                return (
                  <div
                    key={`${video.id}-${i}`}
                    draggable={canEdit}
                    onDragStart={onDragStart(video.id)}
                    onDragOver={onDragOver(video.id)}
                    onDrop={onDrop(video.id)}
                    onDragEnd={() => { setDraggingId(null); setOverId(null) }}
                    style={{
                      outline: isDragOver ? '2px solid var(--accent)' : 'none',
                      outlineOffset: -2,
                      borderRadius: 10,
                      opacity: isBeingDragged ? 0.4 : 1,
                      transition: 'opacity 140ms ease',
                    }}
                  >
                    <QueueRow
                      video={video}
                      duration={formatDuration(video.durationSeconds)}
                      canEdit={canEdit}
                      isNowPlaying={!canEdit && video.id === nowPlayingVideoId}
                      onPlay={() => {
                        if (canEdit) return
                        send({ type: 'playVideo', payload: { videoId: video.id, source: 'queue', contextId: activePlaylist.id } })
                      }}
                      onRemove={() => removeVideo(video.id)}
                    />
                  </div>
                )
              })}
            </div>
          )}
        </div>

        {/* Footer — Clear queue (edit layer only, non-empty) */}
        {canEdit && queueVideos.length > 0 && (
          <div style={{ padding: 12, borderTop: '1px solid rgba(255,255,255,0.08)', flexShrink: 0 }}>
            <button
              className="lt-btn-destructive"
              onClick={() => setShowClearConfirm(true)}
              style={{ width: '100%', justifyContent: 'center' }}
            >
              Clear queue
            </button>
          </div>
        )}
      </div>

      {/* Clear confirmation */}
      {showClearConfirm && (
        <div className="modal-backdrop" role="presentation" style={{ zIndex: 90 }}>
          <div className="modal-panel" role="dialog" aria-modal="true" aria-label="Clear queue" style={{ width: 340, padding: 28 }}>
            <h2 style={{ fontSize: 16, marginBottom: 8 }}>Clear "{activePlaylist.name}"?</h2>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 20 }}>
              This removes every video from the queue. The videos themselves
              aren't deleted.
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="lt-btn-secondary" onClick={() => setShowClearConfirm(false)} style={{ flex: 1, justifyContent: 'center' }}>
                Cancel
              </button>
              <button className="lt-btn-destructive" onClick={clearQueue} style={{ flex: 1, justifyContent: 'center' }}>
                Clear
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

function QueueRow({
  video, duration, canEdit, isNowPlaying, onPlay, onRemove,
}: {
  video: Video
  duration: string
  canEdit: boolean
  isNowPlaying: boolean
  onPlay: () => void
  onRemove: () => void
}) {
  const [hover, setHover] = useState(false)
  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onClick={onPlay}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        padding: 8,
        borderRadius: 10,
        background: isNowPlaying
          ? 'rgba(155,93,229,0.16)'
          : hover && !canEdit ? 'rgba(255,255,255,0.06)' : 'transparent',
        boxShadow: isNowPlaying ? 'inset 0 0 0 1px rgba(155,93,229,0.4)' : 'none',
        cursor: canEdit ? 'grab' : 'pointer',
        transition: 'background 140ms ease, box-shadow 140ms ease',
      }}
    >
      {canEdit && (
        <span style={{ color: 'var(--text-tertiary)', flexShrink: 0, display: 'flex' }}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <circle cx="4" cy="3" r="1" fill="currentColor" /><circle cx="10" cy="3" r="1" fill="currentColor" />
            <circle cx="4" cy="7" r="1" fill="currentColor" /><circle cx="10" cy="7" r="1" fill="currentColor" />
            <circle cx="4" cy="11" r="1" fill="currentColor" /><circle cx="10" cy="11" r="1" fill="currentColor" />
          </svg>
        </span>
      )}
      <div style={{
        position: 'relative', width: 96, height: 54, borderRadius: 7,
        overflow: 'hidden', flexShrink: 0, background: 'rgba(255,255,255,0.04)',
      }}>
        {video.thumbnailPath && (
          <Thumb video={video} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        )}
        {isNowPlaying && (
          <div style={{
            position: 'absolute', inset: 0,
            background: 'rgba(0,0,0,0.45)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 3,
          }}>
            {[0, 1, 2].map(i => (
              <span
                key={i}
                className="lt-eq-bar"
                style={{
                  width: 3, height: 16, borderRadius: 2,
                  background: 'var(--accent)',
                  animationDelay: `${i * 0.18}s`,
                }}
              />
            ))}
          </div>
        )}
        {duration && (
          <div style={{
            position: 'absolute', bottom: 3, right: 3,
            background: 'rgba(0,0,0,0.8)', borderRadius: 3, padding: '1px 4px',
            fontSize: 10, fontWeight: 700, color: 'white',
          }}>
            {duration}
          </div>
        )}
      </div>
      <div
        className="line-clamp-2"
        style={{ flex: 1, minWidth: 0, fontSize: 13, fontWeight: 500, color: 'var(--text-primary)', lineHeight: 1.35 }}
      >
        {video.title}
      </div>
      {canEdit && (
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onRemove() }}
          aria-label="Remove from queue"
          title="Remove from queue"
          style={{
            width: 28, height: 28, borderRadius: 7, flexShrink: 0,
            background: 'rgba(248,113,113,0.14)',
            border: '1px solid rgba(248,113,113,0.32)',
            color: 'var(--destructive)', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0,
          }}
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <path d="M3 3L9 9M9 3L3 9" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
          </svg>
        </button>
      )}
    </div>
  )
}
