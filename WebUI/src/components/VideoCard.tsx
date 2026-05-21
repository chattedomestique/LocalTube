import { memo, useLayoutEffect, useRef } from 'react'
import type { Video } from '../types'
import { thumbUrl } from '../utils'

/**
 * Thumbnail with an eager off-thread decode on mount.
 *
 * The previous "blinking as we scroll" was decoder lag, not decode-time
 * fade absence: browsers defer decoding off-screen images even with
 * loading="eager", so as scroll exposes a thumbnail the decoder runs at
 * that moment and pixels appear with a perceptible pop. A JS fade-in
 * actually made things worse — it exposed a 280 ms gray placeholder
 * before fading in, and stacked with the .reveal card-level fade.
 *
 * The real fix is HTMLImageElement.decode(): call it immediately on
 * mount and the browser eagerly decodes the image on a worker, so by
 * the time the user scrolls the card into view the pixels are ready
 * and the img element paints them on the next frame with no pop.
 *
 * No state, no transitions, no re-renders — the decode call is
 * fire-and-forget. The img element is otherwise identical to a plain
 * <img>; the wrapping .reveal card animation still does the
 * mount-time fade.
 */
export function Thumb({ video, style, className }: {
  video: Pick<Video, 'thumbnailPath' | 'thumbnailVersion'>
  style?: React.CSSProperties
  className?: string
}) {
  const url = thumbUrl(video)
  const imgRef = useRef<HTMLImageElement>(null)

  useLayoutEffect(() => {
    const img = imgRef.current
    if (!img) return
    // .decode() returns a promise that resolves when the image is loaded
    // AND decoded and ready for paint. Calling it without awaiting still
    // schedules the decode eagerly — by the time the img is scrolled
    // into view, it's already decoded so painting is instant.
    img.decode().catch(() => { /* ignore — onError handles real failures */ })
  }, [url])

  if (!url) return null

  return (
    <img
      ref={imgRef}
      src={url}
      alt=""
      className={className}
      loading="eager"
      decoding="async"
      onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
      style={style}
    />
  )
}

interface Props {
  video: Video
  isEditorMode: boolean
  isActiveDownload?: boolean
  onPlay: () => void
  onDelete?: () => void
  onRetry?: () => void
}

function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return ''
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = Math.floor(total % 60)
  if (h > 0) {
    return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  }
  return `${m}:${s.toString().padStart(2, '0')}`
}

function VideoCard({
  video,
  isEditorMode,
  isActiveDownload,
  onPlay,
  onDelete,
  onRetry,
}: Props) {
  const isReady = video.downloadState === 'ready'
  const isDownloading = video.downloadState === 'downloading' || isActiveDownload
  const isQueued = video.downloadState === 'queued'
  const isError = video.downloadState === 'error'
  const hasIssue = !isReady
  const duration = formatDuration(video.durationSeconds)
  const resume = video.resumePositionSeconds > 5

  return (
    <div
      className={isReady ? 'lt-video-card' : undefined}
      onClick={isReady ? onPlay : undefined}
      style={{
        display: 'flex',
        flexDirection: 'column',
        borderRadius: 18,
        overflow: 'hidden',
        background: 'rgba(22,22,27,0.95)',
        border: '0.5px solid rgba(255,255,255,0.13)',
        cursor: isReady ? 'pointer' : 'default',
        opacity: hasIssue ? 0.4 : 1,
        position: 'relative',
        boxShadow: '0 4px 16px rgba(0,0,0,0.35), 0 1px 4px rgba(0,0,0,0.2)',
      }}
    >
      {/* Thumbnail area */}
      <div style={{
        position: 'relative',
        aspectRatio: '16/9',
        overflow: 'hidden',
        background: 'var(--surface-el)',
        flexShrink: 0,
      }}>
        {video.thumbnailPath ? (
          <Thumb
            video={video}
            className="lt-thumb"
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
            }}
          />
        ) : (
          <div style={{
            width: '100%',
            height: '100%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'linear-gradient(135deg, var(--surface-el) 0%, #1e1e28 100%)',
          }}>
            <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
              <rect x="2" y="5" width="28" height="22" rx="4" stroke="var(--text-tertiary)" strokeWidth="1.5" fill="none" />
              <polygon points="12,11 23,16 12,21" fill="var(--text-tertiary)" />
            </svg>
          </div>
        )}

        {/* Downloading overlay */}
        {(isDownloading || isQueued) && (
          <div style={{
            position: 'absolute',
            inset: 0,
            background: 'rgba(0,0,0,0.55)',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 8,
          }}>
            {isQueued ? (
              <>
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
                  <circle cx="12" cy="12" r="9" stroke="rgba(255,255,255,0.3)" strokeWidth="2" />
                  <path d="M8 12h8M12 8v8" stroke="rgba(255,255,255,0.6)" strokeWidth="2" strokeLinecap="round" />
                </svg>
                <span style={{ fontSize: 16, color: 'rgba(255,255,255,0.6)', fontWeight: 600 }}>
                  Queued
                </span>
              </>
            ) : (
              <>
                <svg className="spinner" width="42" height="42" viewBox="0 0 28 28" fill="none">
                  <circle cx="14" cy="14" r="11" stroke="rgba(255,255,255,0.15)" strokeWidth="2.5" />
                  <path d="M14 3A11 11 0 0 1 25 14" stroke="var(--accent)" strokeWidth="2.5" strokeLinecap="round" />
                </svg>
                <div style={{
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  gap: 4,
                }}>
                  <span style={{ fontSize: 16, color: 'rgba(255,255,255,0.7)', fontWeight: 600 }}>
                    {Math.round(video.downloadProgress * 100)}%
                  </span>
                  <div style={{
                    width: 120,
                    height: 5,
                    background: 'rgba(255,255,255,0.15)',
                    borderRadius: 2,
                    overflow: 'hidden',
                  }}>
                    <div style={{
                      height: '100%',
                      width: '100%',
                      transformOrigin: 'left center',
                      transform: `scaleX(${video.downloadProgress})`,
                      background: 'linear-gradient(90deg, var(--accent), var(--accent-hover))',
                      borderRadius: 2,
                      transition: 'transform 300ms ease',
                    }} />
                  </div>
                </div>
              </>
            )}
          </div>
        )}

        {/* Error overlay */}
        {isError && (
          <div style={{
            position: 'absolute',
            inset: 0,
            background: 'rgba(0,0,0,0.7)',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 8,
          }}>
            <div style={{
              width: 52,
              height: 52,
              borderRadius: '50%',
              background: 'rgba(248,113,113,0.2)',
              border: '1px solid rgba(248,113,113,0.4)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <svg width="24" height="24" viewBox="0 0 16 16" fill="none">
                <path d="M8 4V8" stroke="#f87171" strokeWidth="1.5" strokeLinecap="round" />
                <circle cx="8" cy="11" r="0.75" fill="#f87171" />
              </svg>
            </div>
            {onRetry && (
              <button
                className="lt-btn-retry"
                onClick={(e) => { e.stopPropagation(); onRetry?.() }}
              >
                Retry
              </button>
            )}
          </div>
        )}

        {/* Hover play button — CSS-driven visibility via .lt-play-btn */}
        {isReady && !isEditorMode && (
          <div style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            pointerEvents: 'none',
          }}>
            <div
              className="lt-play-btn"
              style={{
                width: 72,
                height: 72,
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                pointerEvents: 'auto',
              }}
            >
              <svg width="22" height="22" viewBox="0 0 16 16" fill="none">
                <polygon points="5,3 14,8 5,13" fill="white" />
              </svg>
            </div>
          </div>
        )}

        {/* Duration badge */}
        {duration && isReady && (
          <div style={{
            position: 'absolute',
            bottom: 7,
            right: 7,
            background: 'rgba(0,0,0,0.65)',
            border: '0.5px solid rgba(255,255,255,0.14)',
            borderRadius: 8,
            padding: '4px 10px',
            fontSize: 15,
            fontWeight: 700,
            color: 'white',
            letterSpacing: '0.02em',
            pointerEvents: 'none',
          }}>
            {duration}
          </div>
        )}

        {/* Resume position bar */}
        {isReady && resume && (
          <div style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            height: 3,
            background: 'rgba(255,255,255,0.15)',
            pointerEvents: 'none',
          }}>
            <div style={{
              height: '100%',
              width: `${Math.min((video.resumePositionSeconds / video.durationSeconds) * 100, 100)}%`,
              background: 'var(--accent)',
            }} />
          </div>
        )}

        {/* Editor delete overlay */}
        {isEditorMode && onDelete && (
          <div className="lt-editor-overlay" style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'rgba(0,0,0,0.4)',
            opacity: 0,
            transition: 'opacity 140ms ease',
            pointerEvents: 'none',
          }}>
            <button
              className="lt-btn-retry"
              onClick={(e) => { e.stopPropagation(); onDelete?.() }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                padding: '12px 20px',
                borderRadius: 12,
                background: 'rgba(248,113,113,0.2)',
                border: '1px solid rgba(248,113,113,0.4)',
                color: 'var(--destructive)',
                fontSize: 16,
                fontWeight: 600,
                cursor: 'pointer',
                pointerEvents: 'auto',
              }}
            >
              <svg width="18" height="18" viewBox="0 0 13 13" fill="none">
                <path d="M2 3.5H11M4.5 3.5V2.5A1 1 0 0 1 5.5 1.5H7.5A1 1 0 0 1 8.5 2.5V3.5M5 6V10M8 6V10" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M3 3.5L3.5 11H9.5L10 3.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Delete
            </button>
          </div>
        )}
      </div>

      {/* Info area — compact: just title + optional resume marker */}
      <div style={{ padding: '10px 14px 12px' }}>
        <p style={{
          fontSize: 17,
          fontWeight: 500,
          color: 'var(--text-primary)',
          lineHeight: 1.35,
          letterSpacing: '-0.01em',
          margin: 0,
        }} className="line-clamp-2">
          {video.title}
        </p>
        {resume && isReady && (
          <p style={{
            fontSize: 14,
            color: 'var(--blue)',
            fontWeight: 500,
            margin: '6px 0 0',
          }}>
            Resume at {formatDuration(video.resumePositionSeconds)}
          </p>
        )}
      </div>
    </div>
  )
}

// Only re-render when the video data itself or editor/active state changes.
// Callback refs (onPlay/onDelete/onRetry) are new arrows every parent render
// but stable in behaviour — excluding them prevents 16 cards re-rendering on
// every download progress tick.
export default memo(VideoCard, (prev, next) =>
  prev.video === next.video &&
  prev.isEditorMode === next.isEditorMode &&
  prev.isActiveDownload === next.isActiveDownload
)
