import type { Channel, Video } from '../types'

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
        borderRadius: 16,
        userSelect: 'none',
        WebkitUserSelect: 'none',
      }}
    >
      {/* Thumbnail */}
      {hasThumbnail ? (
        <img
          src={`localtube-thumb://${thumbVideo.thumbnailPath}`}
          alt=""
          style={{
            position: 'absolute',
            inset: 0,
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            transition: 'transform 0.3s ease',
          }}
          onError={(e) => {
            (e.target as HTMLImageElement).style.display = 'none'
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
        transition: 'opacity 0.2s ease',
      }} />

      {/* Hover glow border */}
      <div style={{
        position: 'absolute',
        inset: 0,
        borderRadius: 15,
        border: '1px solid transparent',
        background: 'transparent',
        transition: 'border-color 0.2s ease',
        pointerEvents: 'none',
      }} className="card-glow-border" />

      {/* Top-right: video count badge */}
      <div style={{
        position: 'absolute',
        top: 10,
        right: 10,
        background: 'rgba(0,0,0,0.7)',
        backdropFilter: 'blur(8px)',
        borderRadius: 8,
        padding: '3px 9px',
        fontSize: 12,
        fontWeight: 600,
        color: 'white',
        display: 'flex',
        alignItems: 'center',
        gap: 4,
        border: '1px solid rgba(255,255,255,0.1)',
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
        padding: '10px 14px 12px',
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
              <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.7)', fontWeight: 500 }}>
                Downloading...
              </span>
              <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.7)' }}>
                {Math.round(downloadProgress * 100)}%
              </span>
            </div>
            <div className="progress-bar-track" style={{ height: 3 }}>
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
            <span style={{ fontSize: 18, lineHeight: 1 }}>{channel.emoji}</span>
          )}
          <div>
            <div style={{
              fontSize: 14,
              fontWeight: 700,
              color: 'white',
              letterSpacing: '-0.01em',
              lineHeight: 1.2,
              textShadow: '0 1px 3px rgba(0,0,0,0.5)',
            }}>
              {channel.displayName}
            </div>
            <div style={{
              fontSize: 11,
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
          top: 10,
          left: 10,
          width: 28,
          height: 28,
          borderRadius: '50%',
          background: 'rgba(0,0,0,0.6)',
          backdropFilter: 'blur(4px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          border: '1px solid rgba(255,255,255,0.1)',
        }}>
          <svg className="spinner" width="14" height="14" viewBox="0 0 14 14" fill="none">
            <circle cx="7" cy="7" r="5.5" stroke="rgba(255,255,255,0.2)" strokeWidth="2" />
            <path d="M7 1.5A5.5 5.5 0 0 1 12.5 7" stroke="var(--accent)" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </div>
      )}
    </div>
  )
}
