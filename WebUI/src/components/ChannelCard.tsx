import type { ReactNode } from 'react'
import type { Channel, Video } from '../types'
import { Thumb } from './VideoCard'

// Shared circular corner button used by the edit-layer affordances on
// the channel card. Three tones — destructive (×), neutral (hide), and
// positive (unhide) — all the same shape so they read as a button row.
function EditCornerButton({
  onClick, title, ariaLabel, icon, tone,
}: {
  onClick: () => void
  title: string
  ariaLabel: string
  icon: ReactNode
  tone: 'destructive' | 'neutral' | 'positive'
}) {
  const palette = (() => {
    switch (tone) {
      case 'destructive':
        return { bg: 'rgba(248,113,113,0.88)', border: 'rgba(255,255,255,0.35)', color: 'white' }
      case 'positive':
        return { bg: 'rgba(96,165,250,0.88)', border: 'rgba(255,255,255,0.32)', color: 'white' }
      case 'neutral':
        return { bg: 'rgba(0,0,0,0.62)', border: 'rgba(255,255,255,0.28)', color: 'white' }
    }
  })()
  return (
    <button
      type="button"
      onClick={(e) => { e.stopPropagation(); onClick() }}
      title={title}
      aria-label={ariaLabel}
      style={{
        width: 32,
        height: 32,
        borderRadius: '50%',
        background: palette.bg,
        border: `1px solid ${palette.border}`,
        color: palette.color,
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 0,
        boxShadow: '0 4px 12px rgba(0,0,0,0.42)',
        backdropFilter: 'blur(12px)',
        WebkitBackdropFilter: 'blur(12px)',
        transition: 'transform 160ms cubic-bezier(0.25,1,0.5,1)',
      }}
      onMouseEnter={e => { e.currentTarget.style.transform = 'scale(1.10)' }}
      onMouseLeave={e => { e.currentTarget.style.transform = 'scale(1)' }}
    >
      {icon}
    </button>
  )
}

interface Props {
  channel: Channel
  videos: Video[]
  isDownloading?: boolean
  downloadProgress?: number
  onClick: () => void
  /** True when the parent is in the inline edit layer for this profile.
      Adds drag handle + remove-from-profile button; click is a no-op. */
  isEditing?: boolean
  /** True when this channel is currently hidden from the active profile.
      Visible only in edit layer; viewer mode filters hidden channels out
      of the grid entirely. */
  isHidden?: boolean
  /** Called when the parent clicks the × button while editing. */
  onRemoveFromProfile?: () => void
  /** Called when the parent toggles the hide/unhide eye button. */
  onToggleHidden?: () => void
}

// "New" = a video became ready within the last NEW_VIDEO_WINDOW_MS. Stays
// up for ~3 days so kids notice fresh content between sessions but it
// doesn't linger forever on every channel.
const NEW_VIDEO_WINDOW_MS = 1000 * 60 * 60 * 24 * 3

export default function ChannelCard({
  channel, videos, isDownloading, downloadProgress, onClick,
  isEditing, isHidden, onRemoveFromProfile, onToggleHidden,
}: Props) {
  const readyVideos = videos.filter(v => v.downloadState === 'ready')

  // Image priority for the card:
  //   1. Channel banner (YouTube header art — looks like a channel)
  //   2. Most recent ready video's thumbnail (fallback for non-source
  //      channels and channels without a banner yet)
  //   3. Emoji placeholder
  const bannerSrc = channel.bannerPath || null
  const thumbVideo = readyVideos[0] ?? videos[0]
  const hasFallbackThumb = !bannerSrc && thumbVideo?.thumbnailPath

  // Most recent download time across this channel's ready videos.
  // If that's within NEW_VIDEO_WINDOW_MS, show a soft "new" badge.
  const lastReadyAt = readyVideos.reduce<number>((acc, v) => {
    const t = v.downloadedAt ? Date.parse(v.downloadedAt) : 0
    return t > acc ? t : acc
  }, 0)
  const hasNewVideo = lastReadyAt > 0 && (Date.now() - lastReadyAt) < NEW_VIDEO_WINDOW_MS

  return (
    <div
      className="lt-card"
      onClick={isEditing ? undefined : onClick}
      style={{
        aspectRatio: '16/9',
        position: 'relative',
        overflow: 'hidden',
        cursor: isEditing ? 'grab' : 'pointer',
        borderRadius: 22,
        userSelect: 'none',
        WebkitUserSelect: 'none',
        // Hidden channels read as dimmed in the edit layer so the
        // parent can see what's hidden without it competing visually
        // with the visible cards.
        opacity: isEditing && isHidden ? 0.45 : 1,
        transition: 'opacity 200ms ease',
      }}
    >
      {/* Card image — prefer YouTube channel banner, fall back to most
          recent ready video thumbnail, then to an emoji placeholder. */}
      {bannerSrc ? (
        <img
          src={bannerSrc}
          alt=""
          className="lt-thumb"
          loading="eager"
          decoding="async"
          onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
          style={{
            position: 'absolute',
            inset: 0,
            width: '100%',
            height: '100%',
            objectFit: 'cover',
          }}
        />
      ) : hasFallbackThumb ? (
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

      {/* Edit-layer affordances — drag handle (centered) + remove-from-
          profile × (top-right). Both appear only while the parent is in
          edit layer. Drag is wired at the grid level (parent handles
          dragstart/over/drop); this is just the visual handle. */}
      {isEditing && (
        <>
          {/* Drag handle — full-card subtle overlay so the whole card
              feels grabbable, plus an icon hint top-left. */}
          <div style={{
            position: 'absolute',
            inset: 0,
            background: 'rgba(0,0,0,0.18)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 2,
            pointerEvents: 'none',
          }}>
            <div style={{
              padding: '10px 14px',
              borderRadius: 99,
              background: 'rgba(0,0,0,0.55)',
              backdropFilter: 'blur(16px) saturate(180%)',
              WebkitBackdropFilter: 'blur(16px) saturate(180%)',
              border: '1px solid rgba(255,255,255,0.2)',
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              color: 'white',
              fontSize: 13,
              fontWeight: 600,
            }}>
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <circle cx="4" cy="3" r="1" fill="currentColor" />
                <circle cx="10" cy="3" r="1" fill="currentColor" />
                <circle cx="4" cy="7" r="1" fill="currentColor" />
                <circle cx="10" cy="7" r="1" fill="currentColor" />
                <circle cx="4" cy="11" r="1" fill="currentColor" />
                <circle cx="10" cy="11" r="1" fill="currentColor" />
              </svg>
              Drag to reorder
            </div>
          </div>
          {/* Edit-layer corner buttons — × (remove) on top, eye toggle
              (hide/unhide) below. Both sit above the dim overlay and the
              hide overlay so they're always tappable. */}
          <div style={{
            position: 'absolute',
            top: 12,
            right: 12,
            zIndex: 3,
            display: 'flex',
            flexDirection: 'column',
            gap: 8,
            alignItems: 'flex-end',
          }}>
            {onRemoveFromProfile && (
              <EditCornerButton
                onClick={onRemoveFromProfile}
                title="Remove from this profile"
                ariaLabel="Remove channel from profile"
                tone="destructive"
                icon={(
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                    <path d="M3 3L11 11M11 3L3 11" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                  </svg>
                )}
              />
            )}
            {onToggleHidden && (
              <EditCornerButton
                onClick={onToggleHidden}
                title={isHidden ? 'Unhide channel' : 'Hide from this profile'}
                ariaLabel={isHidden ? 'Unhide channel' : 'Hide channel'}
                tone={isHidden ? 'positive' : 'neutral'}
                icon={isHidden ? (
                  // open eye → click to unhide
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z" stroke="currentColor" strokeWidth="1.4" fill="none" />
                    <circle cx="8" cy="8" r="2" stroke="currentColor" strokeWidth="1.4" fill="none" />
                  </svg>
                ) : (
                  // crossed eye → click to hide
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z" stroke="currentColor" strokeWidth="1.4" fill="none" />
                    <path d="M2 2L14 14" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
                  </svg>
                )}
              />
            )}
          </div>

          {/* "Hidden" pill — bottom-center of the card while editing,
              only when actually hidden. Tells the parent at a glance
              what's hidden in this profile. */}
          {isHidden && (
            <div style={{
              position: 'absolute',
              bottom: 14,
              left: '50%',
              transform: 'translateX(-50%)',
              zIndex: 3,
              padding: '5px 12px',
              borderRadius: 99,
              background: 'rgba(0,0,0,0.75)',
              border: '1px solid rgba(255,255,255,0.22)',
              backdropFilter: 'blur(12px)',
              WebkitBackdropFilter: 'blur(12px)',
              color: 'rgba(255,255,255,0.92)',
              fontSize: 12,
              fontWeight: 700,
              letterSpacing: '0.04em',
              textTransform: 'uppercase',
              display: 'flex',
              alignItems: 'center',
              gap: 6,
            }}>
              <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
                <path d="M1.5 5.5s1.5-3 4-3 4 3 4 3-1.5 3-4 3-4-3-4-3z" stroke="currentColor" strokeWidth="1.2" fill="none" />
                <path d="M1.5 1.5L9.5 9.5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
              </svg>
              Hidden
            </div>
          )}
        </>
      )}

      {/* "New video" badge — soft glowing dot in the top-left corner
          when a video became ready in the last few days. Designed to
          feel ambient (blurred halo) rather than a hard notification
          dot. Sits above the gradient overlay (zIndex 1). */}
      {hasNewVideo && (
        <div
          title="New video"
          aria-label="New video"
          style={{
            position: 'absolute',
            top: 14,
            left: 14,
            zIndex: 1,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            pointerEvents: 'none',
          }}
        >
          {/* Outer glow */}
          <div style={{
            position: 'absolute',
            width: 28,
            height: 28,
            borderRadius: '50%',
            background: 'rgba(155,93,229,0.55)',
            filter: 'blur(10px)',
          }} />
          {/* Inner dot */}
          <div style={{
            position: 'relative',
            width: 12,
            height: 12,
            borderRadius: '50%',
            background: 'var(--accent)',
            boxShadow: '0 0 0 2px rgba(13,13,15,0.65), 0 0 12px rgba(155,93,229,0.7)',
          }} />
        </div>
      )}

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
