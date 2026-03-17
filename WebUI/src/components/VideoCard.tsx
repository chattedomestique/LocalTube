import { useState } from 'react'
import type { Video } from '../types'

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
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = seconds % 60
  if (h > 0) {
    return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  }
  return `${m}:${s.toString().padStart(2, '0')}`
}

function formatDate(dateStr: string): string {
  if (!dateStr) return ''
  try {
    const d = new Date(dateStr)
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  } catch {
    return ''
  }
}

export default function VideoCard({
  video,
  isEditorMode,
  isActiveDownload,
  onPlay,
  onDelete,
  onRetry,
}: Props) {
  const [hovered, setHovered] = useState(false)
  const isReady = video.downloadState === 'ready'
  const isDownloading = video.downloadState === 'downloading' || isActiveDownload
  const isQueued = video.downloadState === 'queued'
  const isError = video.downloadState === 'error'
  const duration = formatDuration(video.durationSeconds)
  const resume = video.resumePositionSeconds > 5

  const handleClick = () => {
    if (isReady) {
      onPlay()
    }
  }

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onClick={handleClick}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 0,
        borderRadius: 14,
        overflow: 'hidden',
        background: 'var(--surface)',
        border: '1px solid',
        borderColor: hovered && isReady ? 'var(--border-strong)' : 'var(--border)',
        cursor: isReady ? 'pointer' : 'default',
        transition: 'all 0.15s ease',
        transform: hovered && isReady ? 'translateY(-2px)' : 'translateY(0)',
        boxShadow: hovered && isReady ? 'var(--shadow-md)' : 'none',
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
        {/* Thumbnail image */}
        {video.thumbnailPath ? (
          <img
            src={`localtube-thumb://${video.thumbnailPath}`}
            alt=""
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              transition: 'transform 0.3s ease',
              transform: hovered && isReady ? 'scale(1.04)' : 'scale(1)',
              filter: (!isReady && !isDownloading) ? 'brightness(0.5)' : 'none',
            }}
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = 'none'
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

        {/* Duration badge */}
        {duration && isReady && (
          <div style={{
            position: 'absolute',
            bottom: 7,
            right: 7,
            background: 'rgba(0,0,0,0.85)',
            borderRadius: 5,
            padding: '2px 6px',
            fontSize: 11,
            fontWeight: 700,
            color: 'white',
            letterSpacing: '0.02em',
            backdropFilter: 'blur(4px)',
          }}>
            {duration}
          </div>
        )}

        {/* Resume position indicator */}
        {isReady && resume && (
          <div style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            height: 3,
            background: 'rgba(255,255,255,0.15)',
          }}>
            <div style={{
              height: '100%',
              width: `${Math.min((video.resumePositionSeconds / video.durationSeconds) * 100, 100)}%`,
              background: 'var(--accent)',
              borderRadius: 0,
            }} />
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
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
                  <circle cx="12" cy="12" r="9" stroke="rgba(255,255,255,0.3)" strokeWidth="2" />
                  <path d="M8 12h8M12 8v8" stroke="rgba(255,255,255,0.6)" strokeWidth="2" strokeLinecap="round" />
                </svg>
                <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.6)', fontWeight: 600 }}>
                  Queued
                </span>
              </>
            ) : (
              <>
                <svg className="spinner" width="28" height="28" viewBox="0 0 28 28" fill="none">
                  <circle cx="14" cy="14" r="11" stroke="rgba(255,255,255,0.15)" strokeWidth="2.5" />
                  <path d="M14 3A11 11 0 0 1 25 14" stroke="var(--accent)" strokeWidth="2.5" strokeLinecap="round" />
                </svg>
                <div style={{
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  gap: 4,
                }}>
                  <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.7)', fontWeight: 600 }}>
                    {Math.round(video.downloadProgress * 100)}%
                  </span>
                  <div style={{
                    width: 80,
                    height: 3,
                    background: 'rgba(255,255,255,0.15)',
                    borderRadius: 2,
                    overflow: 'hidden',
                  }}>
                    <div style={{
                      height: '100%',
                      width: `${Math.round(video.downloadProgress * 100)}%`,
                      background: 'linear-gradient(90deg, var(--accent), var(--accent-hover))',
                      borderRadius: 2,
                      transition: 'width 300ms ease',
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
              width: 36,
              height: 36,
              borderRadius: '50%',
              background: 'rgba(248,113,113,0.2)',
              border: '1px solid rgba(248,113,113,0.4)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M8 4V8" stroke="#f87171" strokeWidth="1.5" strokeLinecap="round" />
                <circle cx="8" cy="11" r="0.75" fill="#f87171" />
              </svg>
            </div>
            {onRetry && (
              <button
                onClick={(e) => { e.stopPropagation(); onRetry?.() }}
                style={{
                  fontSize: 11,
                  fontWeight: 600,
                  color: 'var(--destructive)',
                  background: 'rgba(248,113,113,0.15)',
                  border: '1px solid rgba(248,113,113,0.3)',
                  borderRadius: 6,
                  padding: '3px 8px',
                  cursor: 'pointer',
                }}
              >
                Retry
              </button>
            )}
          </div>
        )}

        {/* Hover play button */}
        {isReady && hovered && !isEditorMode && (
          <div style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'rgba(0,0,0,0.3)',
          }}>
            <div style={{
              width: 44,
              height: 44,
              borderRadius: '50%',
              background: 'rgba(255,255,255,0.95)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 2px 12px rgba(0,0,0,0.4)',
            }}>
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none" style={{ marginLeft: 2 }}>
                <polygon points="5,3 14,8 5,13" fill="#0d0d0f" />
              </svg>
            </div>
          </div>
        )}

        {/* Editor delete overlay */}
        {isEditorMode && hovered && onDelete && (
          <div style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'rgba(0,0,0,0.4)',
          }}>
            <button
              onClick={(e) => { e.stopPropagation(); onDelete?.() }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                padding: '8px 14px',
                borderRadius: 8,
                background: 'rgba(248,113,113,0.2)',
                border: '1px solid rgba(248,113,113,0.4)',
                color: 'var(--destructive)',
                fontSize: 12,
                fontWeight: 600,
                cursor: 'pointer',
                backdropFilter: 'blur(4px)',
              }}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M2 3.5H11M4.5 3.5V2.5A1 1 0 0 1 5.5 1.5H7.5A1 1 0 0 1 8.5 2.5V3.5M5 6V10M8 6V10" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M3 3.5L3.5 11H9.5L10 3.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Delete
            </button>
          </div>
        )}
      </div>

      {/* Info area */}
      <div style={{ padding: '10px 12px 12px' }}>
        <p style={{
          fontSize: 13,
          fontWeight: 500,
          color: isReady ? 'var(--text-primary)' : 'var(--text-secondary)',
          lineHeight: 1.4,
          letterSpacing: '-0.01em',
        }} className="line-clamp-2">
          {video.title}
        </p>
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          marginTop: 6,
        }}>
          {/* Download state badge */}
          {isReady && (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: 3,
              fontSize: 11,
              color: 'var(--success)',
              fontWeight: 500,
            }}>
              <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                <circle cx="5" cy="5" r="4" fill="none" stroke="#34d399" strokeWidth="1.5" />
                <path d="M3 5L4.5 6.5L7.5 3.5" stroke="#34d399" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Ready
            </div>
          )}
          {isError && (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: 3,
              fontSize: 11,
              color: 'var(--destructive)',
              fontWeight: 500,
            }}>
              <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                <circle cx="5" cy="5" r="4" fill="none" stroke="#f87171" strokeWidth="1.5" />
                <path d="M5 3V5.5" stroke="#f87171" strokeWidth="1.3" strokeLinecap="round" />
                <circle cx="5" cy="7" r="0.5" fill="#f87171" />
              </svg>
              Error
            </div>
          )}
          {(isDownloading) && (
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: 3,
              fontSize: 11,
              color: 'var(--accent)',
              fontWeight: 500,
            }}>
              <svg className="spinner" width="10" height="10" viewBox="0 0 10 10" fill="none">
                <circle cx="5" cy="5" r="3.5" stroke="rgba(155,93,229,0.3)" strokeWidth="1.5" />
                <path d="M5 1.5A3.5 3.5 0 0 1 8.5 5" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              {Math.round(video.downloadProgress * 100)}%
            </div>
          )}
          {isQueued && (
            <div style={{
              fontSize: 11,
              color: 'var(--text-tertiary)',
              fontWeight: 500,
            }}>
              Queued
            </div>
          )}

          {resume && isReady && (
            <>
              <span style={{ color: 'var(--text-tertiary)', fontSize: 11 }}>·</span>
              <span style={{ fontSize: 11, color: 'var(--blue)' }}>
                Resume {formatDuration(video.resumePositionSeconds)}
              </span>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
