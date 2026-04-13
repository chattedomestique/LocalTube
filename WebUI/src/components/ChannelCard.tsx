import type { Channel, Video } from '../types'
import { thumbUrl } from '../utils'
import { Thumb } from './VideoCard'

interface Props {
  channel: Channel
  videos: Video[]
  isDownloading?: boolean
  downloadProgress?: number
  onClick: () => void
}

function formatDuration(seconds: number): string {
  if (seconds <= 0) return ''
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = seconds % 60
  if (h > 0) return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  return `${m}:${s.toString().padStart(2, '0')}`
}

export default function ChannelCard({ channel, videos, isDownloading, downloadProgress, onClick }: Props) {
  const readyVideos = videos.filter(v => v.downloadState === 'ready')
  const thumbVideo = readyVideos[0] ?? videos[0]
  const hasThumbnail = thumbVideo?.thumbnailPath

  return (
    <div
      className="lt-card"
      onClick={onClick}
      style={{
        aspectRatio: '16/9',
        position: 'relative',
        overflow: 'hidden',
        cursor: 'pointer',
        borderRadius: 22,
        userSelect: 'none',
        WebkitUserSelect: 'none',
      }}
    >
      {/* Thumbnail */}
      {hasThumbnail ? (
        <Thumb
          video={thumbVideo!}
          className="lt-thumb"
          style={{
            position: 'absolute',
            inset: 0,
            width: '100%',
            height: '100%',
            objectFit: 'cover',
          }}
        />
      ) : (
        // Placeholder when no thumbnail
        <div style={{
          position: 'absolute',
          inset: 0,
          background: `linear-gradient(135deg, var(--surface-el) 0%, #1e1e28 100%)`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <div style={{ fontSize: 48, opacity: 0.5 }}>
            {channel.emoji ?? '📺'}
          </div>
        </div>
      )}

      {/* Gradient overlay */}
      <div style={{
        position: 'absolute',
        inset: 0,
        background: 'linear-gradient(to top, rgba(0,0,0,0.85) 0%, rgba(0,0,0,0.2) 50%, rgba(0,0,0,0.05) 100%)',
        transition: 'opacity 140ms cubic-bezier(0.89,0,0.14,1)',
      }} />

      {/* Hover glow border — transition now lives in .card-glow-border CSS rule */}
      <div style={{
        position: 'absolute',
        inset: 0,
        borderRadius: 21,
        border: '1px solid transparent',
        background: 'transparent',
        pointerEvents: 'none',
      }} className="card-glow-border" />

      {/* Top-right: video count badge */}
      <div style={{
        position: 'absolute',
        top: 14,
        right: 14,
        background: 'linear-gradient(135deg, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.45) 100%)',
        backdropFilter: 'blur(16px) saturate(180%)',
        WebkitBackdropFilter: 'blur(16px) saturate(180%)',
        border: '0.5px solid rgba(255,255,255,0.18)',
        boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.1)',
        borderRadius: 12,
        padding: '5px 14px',
        fontSize: 16,
        fontWeight: 600,
        color: 'white',
        display: 'flex',
        alignItems: 'center',
        gap: 4,
      }}>
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <rect x="0.5" y="0.5" width="4" height="4" rx="0.75" fill="currentColor" opacity="0.8" />
          <rect x="5.5" y="0.5" width="4" height="4" rx="0.75" fill="currentColor" opacity="0.8" />
          <rect x="0.5" y="5.5" width="4" height="4" rx="0.75" fill="currentColor" opacity="0.8" />
          <rect x="5.5" y="5.5" width="4" height="4" rx="0.75" fill="currentColor" opacity="0.8" />
        </svg>
        {videos.length}
      </div>

      {/* Bottom: channel info */}
      <div style={{
        position: 'absolute',
        bottom: 0,
        left: 0,
        right: 0,
        padding: '16px 20px 20px',
      }}>
        {/* Download progress bar */}
        {isDownloading && downloadProgress !== undefined && (
          <div style={{ marginBottom: 8 }}>
            <div style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginBottom: 4,
            }}>
              <span style={{ fontSize: 15, color: 'rgba(255,255,255,0.7)', fontWeight: 500 }}>
                Downloading...
              </span>
              <span style={{ fontSize: 15, color: 'rgba(255,255,255,0.7)' }}>
                {Math.round(downloadProgress * 100)}%
              </span>
            </div>
            <div className="progress-bar-track" style={{ height: 5 }}>
              <div
                className="progress-bar-fill"
                style={{ width: `${Math.round(downloadProgress * 100)}%` }}
              />
            </div>
          </div>
        )}

        {/* Channel name + emoji */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          {channel.emoji && (
            <span style={{ fontSize: 36, lineHeight: 1 }}>{channel.emoji}</span>
          )}
          <div>
            <div style={{
              fontSize: 26,
              fontWeight: 700,
              color: 'white',
              letterSpacing: '-0.01em',
              lineHeight: 1.2,
              textShadow: '0 2px 8px rgba(0,0,0,0.7)',
            }}>
              {channel.displayName}
            </div>
            <div style={{
              fontSize: 17,
              color: 'rgba(255,255,255,0.55)',
              marginTop: 2,
            }}>
              {readyVideos.length} of {videos.length} ready
            </div>
          </div>
        </div>
      </div>

      {/* Downloading spinner overlay */}
      {isDownloading && (
        <div style={{
          position: 'absolute',
          top: 14,
          left: 14,
          width: 40,
          height: 40,
          borderRadius: '50%',
          background: 'linear-gradient(135deg, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.45) 100%)',
          backdropFilter: 'blur(16px) saturate(180%)',
          WebkitBackdropFilter: 'blur(16px) saturate(180%)',
          border: '0.5px solid rgba(255,255,255,0.16)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <svg className="spinner" width="20" height="20" viewBox="0 0 14 14" fill="none">
            <circle cx="7" cy="7" r="5.5" stroke="rgba(255,255,255,0.2)" strokeWidth="2" />
            <path d="M7 1.5A5.5 5.5 0 0 1 12.5 7" stroke="var(--accent)" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </div>
      )}
    </div>
  )
}
