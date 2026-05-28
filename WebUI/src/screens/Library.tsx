import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react'
import { useAppStore } from '../store'
import ChannelCard from '../components/ChannelCard'
import ProfileAvatar from '../components/ProfileAvatar'
import AmbientBackground from '../components/AmbientBackground'
import { Thumb } from '../components/VideoCard'
import type { Channel, Profile, Video } from '../types'

type LibraryTab = 'channels' | 'playlists' | 'feed'
type ChannelSort = 'custom' | 'name' | 'recent'

const TAB_STORAGE_KEY = 'lt-library-tab'
const SORT_STORAGE_KEY = 'lt-channels-sort'

function readTab(): LibraryTab {
  const v = localStorage.getItem(TAB_STORAGE_KEY)
  return v === 'playlists' || v === 'feed' ? v : 'channels'
}
function readSort(): ChannelSort {
  const v = localStorage.getItem(SORT_STORAGE_KEY)
  return v === 'name' || v === 'recent' ? v : 'custom'
}

export default function Library() {
  const { state, navigateTo, send } = useAppStore()
  const {
    channels, videos, appMode, activeDownload, profiles, profileChannels,
    activeProfileId, isEditing, profileHiddenChannels,
  } = state

  // Tab + sort state — both persisted to localStorage so they survive
  // navigation away (Channel page) and back. Read once on mount; writes
  // happen in the setters below.
  const [tab, setTab] = useState<LibraryTab>(readTab)
  const [sort, setSort] = useState<ChannelSort>(readSort)
  useEffect(() => { localStorage.setItem(TAB_STORAGE_KEY, tab) }, [tab])
  useEffect(() => { localStorage.setItem(SORT_STORAGE_KEY, sort) }, [sort])

  const hiddenIds = useMemo(
    () => new Set(activeProfileId ? (profileHiddenChannels[activeProfileId] ?? []) : []),
    [activeProfileId, profileHiddenChannels]
  )

  // Visible-channel computation:
  //   - Admin sees every channel (legacy fallback).
  //   - Viewer with active profile sees only assigned channels, in the
  //     order stored in profile_channels (per-profile sort).
  //   - Viewer without a profile (fresh install, no profiles) sees all
  //     channels in global sort order.
  const assignedIds: string[] | null =
    activeProfileId ? (profileChannels[activeProfileId] ?? []) : null

  // Apply per-profile sort first, then the user-selected sort overlay.
  // In edit layer the parent always sees hidden channels too (dimmed +
  // labelled). In plain viewer mode hidden channels are filtered out.
  const sortedChannels = useMemo(() => {
    let base: Channel[]
    if (appMode === 'editor' || !assignedIds) {
      base = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)
    } else {
      const byId = new Map(channels.map(c => [c.id, c] as const))
      base = assignedIds
        .map(id => byId.get(id))
        .filter((c): c is typeof channels[number] => c !== undefined)
    }
    // Apply user sort overlay
    if (sort === 'name') {
      base = [...base].sort((a, b) =>
        a.displayName.localeCompare(b.displayName, undefined, { sensitivity: 'base' })
      )
    } else if (sort === 'recent') {
      base = [...base].sort((a, b) => channelActivity(b, videos) - channelActivity(a, videos))
    }
    return base
  }, [channels, assignedIds, appMode, sort, videos])

  const visibleChannels = useMemo(() => {
    // In edit layer, show hidden channels too so parent can manage them.
    if (isEditing) return sortedChannels
    return sortedChannels.filter(c => !hiddenIds.has(c.id))
  }, [sortedChannels, isEditing, hiddenIds])

  const activeProfile = profiles.find(p => p.id === activeProfileId) ?? null
  const showEditAffordances = isEditing && !!activeProfileId

  // Drag-reorder state. Live during a drag only; reorder is committed
  // on drop via setProfileChannels (full canonical order replacement).
  const [draggingId, setDraggingId] = useState<string | null>(null)
  const [overId, setOverId] = useState<string | null>(null)

  // Ambient background sources: every visible channel's banner. Each
  // banner cycles in for ~9s with a soft crossfade — same blur stack as
  // the channel page. If no banners exist yet we fall back to first
  // video thumbnails so the bg still has something to chew on.
  const ambientSources = useMemo(() => {
    const fromBanners = visibleChannels
      .map(c => c.bannerPath)
      .filter((b): b is string => !!b)
    if (fromBanners.length > 0) return fromBanners
    // Fallback: first ready thumbnail per channel
    const fromThumbs: string[] = []
    for (const c of visibleChannels) {
      const list = videos[c.id] ?? []
      const v = list.find(x => x.downloadState === 'ready' && x.thumbnailPath)
      if (v?.thumbnailPath) fromThumbs.push(v.thumbnailPath)
    }
    return fromThumbs
  }, [visibleChannels, videos])

  const handleChannelClick = (channelId: string) => {
    if (showEditAffordances) return  // editing — block navigation
    navigateTo({ screen: 'channel', channelId })
  }

  const handleEditorToggle = () => {
    if (appMode === 'editor') {
      send({ type: 'exitEditorMode' })
    } else {
      send({ type: 'requestEditorMode' })
    }
  }

  // ── Edit-layer mutations ──────────────────────────────────────────────
  const reorderChannels = (newOrder: string[]) => {
    if (!activeProfileId) return
    send({
      type: 'setProfileChannels',
      payload: { profileId: activeProfileId, channelIds: newOrder },
    })
  }

  const removeChannelFromProfile = (channelId: string) => {
    if (!activeProfileId || !assignedIds) return
    reorderChannels(assignedIds.filter(id => id !== channelId))
  }

  const toggleChannelHidden = (channelId: string) => {
    if (!activeProfileId) return
    const isCurrentlyHidden = hiddenIds.has(channelId)
    send({
      type: 'toggleChannelHidden',
      payload: { profileId: activeProfileId, channelId, hidden: !isCurrentlyHidden },
    })
  }

  // Drag handlers — HTML5 DnD. Only active while edit layer is on.
  // Drop computes the new order from the canonical assignment list
  // (not from the rendered order, which might differ if a video was
  // mid-add) and dispatches the full replacement.
  const onDragStart = (id: string) => (e: React.DragEvent) => {
    if (!showEditAffordances) return
    setDraggingId(id)
    e.dataTransfer.effectAllowed = 'move'
    // Required for Firefox-like behaviour; otherwise drag never starts.
    e.dataTransfer.setData('text/plain', id)
  }
  const onDragOver = (id: string) => (e: React.DragEvent) => {
    if (!showEditAffordances || !draggingId || id === draggingId) return
    e.preventDefault()
    if (overId !== id) setOverId(id)
  }
  const onDrop = (targetId: string) => (e: React.DragEvent) => {
    if (!showEditAffordances || !draggingId || !assignedIds) return
    e.preventDefault()
    const without = assignedIds.filter(x => x !== draggingId)
    const targetIdx = without.indexOf(targetId)
    if (targetIdx === -1) return
    const newOrder = [
      ...without.slice(0, targetIdx),
      draggingId,
      ...without.slice(targetIdx),
    ]
    reorderChannels(newOrder)
    setDraggingId(null)
    setOverId(null)
  }
  const onDragEnd = () => {
    setDraggingId(null)
    setOverId(null)
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

        {/* Right actions.
            - Plain viewer + active profile: profile chip + Edit
            - Edit layer (viewer + isEditing): banner + Admin + Exit Edit
            - Viewer without profile (fresh install): Admin entry */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
        } as CSSProperties}>
          {showEditAffordances && activeProfile ? (
            <>
              <EditingBanner profile={activeProfile} />
              <TopBarButton
                kind="secondary"
                onClick={() => send({ type: 'requestEditorMode' })}
                label="Admin"
                icon={(
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                    <path d="M10 1.5L12.5 4L4.5 12H2V9.5L10 1.5Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" fill="none" />
                  </svg>
                )}
              />
              <TopBarButton
                kind="exit"
                onClick={() => send({ type: 'endEditMode' })}
                label="Done"
                icon={(
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                    <path d="M3 7L6 10L11 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              />
            </>
          ) : activeProfile ? (
            <>
              <TopBarButton
                kind="secondary"
                onClick={() => send({ type: 'requestEditMode' })}
                label="Edit"
                icon={(
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                    <path d="M10 1.5L12.5 4L4.5 12H2V9.5L10 1.5Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" fill="none" />
                  </svg>
                )}
              />
              <ProfileChip profile={activeProfile} onClick={() =>
                send({ type: 'setActiveProfile', payload: { profileId: null } })
              } />
            </>
          ) : (
            <TopBarButton
              kind="secondary"
              onClick={handleEditorToggle}
              label="Admin"
              icon={(
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M10 1.5L12.5 4L4.5 12H2V9.5L10 1.5Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" fill="none" />
                </svg>
              )}
            />
          )}
        </div>
      </div>

      {/* Tab nav — only shown when a profile is active (the picker
          parts of the app don't get tabs). Sits as a sub-bar under the
          main top bar so the chrome stays clean. */}
      {activeProfile && (
        <div style={{
          position: 'relative',
          zIndex: 1,
          display: 'flex',
          alignItems: 'center',
          padding: '0 40px',
          height: 48,
          background: 'rgba(13,13,15,0.55)',
          backdropFilter: 'blur(20px)',
          WebkitBackdropFilter: 'blur(20px)',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          gap: 4,
          flexShrink: 0,
        }}>
          <TabBtn label="Channels" active={tab === 'channels'} onClick={() => setTab('channels')} />
          <TabBtn label="Playlists" active={tab === 'playlists'} onClick={() => setTab('playlists')} />
          <TabBtn label="Feed"      active={tab === 'feed'}      onClick={() => setTab('feed')} />
          <div style={{ flex: 1 }} />
          {showEditAffordances && (
            <AutoplayPicker
              value={activeProfile.autoPlaybackMode ?? 'exit'}
              onChange={(mode) =>
                send({ type: 'setAutoPlaybackMode', payload: { profileId: activeProfile.id, mode } })
              }
            />
          )}
          {tab === 'channels' && visibleChannels.length > 0 && (
            <SortDropdown value={sort} onChange={setSort} />
          )}
        </div>
      )}

      {/* Content */}
      <div style={{
        position: 'relative',
        zIndex: 1,
        flex: 1,
        overflowY: 'auto',
        padding: '44px',
      }}>
        {tab === 'channels' && (
          visibleChannels.length === 0 ? (
            <EmptyChannelsState
              appMode={appMode}
              onOpenAdmin={() => navigateTo({ screen: 'editor' })}
            />
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
                  {visibleChannels.length} {visibleChannels.length === 1 ? 'channel' : 'channels'}
                </span>
              </div>

              {/* Grid */}
              <div style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))',
                gap: 24,
              }}>
                {visibleChannels.map(channel => {
                  const channelVideos = videos[channel.id] ?? []
                  const isDownloading = channelVideos.some(
                    v => v.downloadState === 'downloading' || v.downloadState === 'queued'
                  )
                  const downloadingVideo = channelVideos.find(
                    v => v.downloadState === 'downloading'
                  )
                  const isDragOver = showEditAffordances && overId === channel.id && draggingId !== channel.id
                  const isBeingDragged = showEditAffordances && draggingId === channel.id
                  const isHidden = hiddenIds.has(channel.id)
                  return (
                    <div
                      key={channel.id}
                      draggable={showEditAffordances}
                      onDragStart={onDragStart(channel.id)}
                      onDragOver={onDragOver(channel.id)}
                      onDrop={onDrop(channel.id)}
                      onDragEnd={onDragEnd}
                      style={{
                        outline: isDragOver ? '2px solid var(--accent)' : 'none',
                        outlineOffset: 2,
                        borderRadius: 22,
                        opacity: isBeingDragged ? 0.4 : 1,
                        transform: isBeingDragged ? 'scale(0.98)' : 'scale(1)',
                        transition: 'opacity 160ms ease, transform 160ms ease, outline-color 160ms ease',
                      }}
                    >
                      <ChannelCard
                        channel={channel}
                        videos={channelVideos}
                        isDownloading={isDownloading}
                        downloadProgress={downloadingVideo?.downloadProgress}
                        onClick={() => handleChannelClick(channel.id)}
                        isEditing={showEditAffordances}
                        isHidden={isHidden}
                        onRemoveFromProfile={
                          showEditAffordances
                            ? () => removeChannelFromProfile(channel.id)
                            : undefined
                        }
                        onToggleHidden={
                          showEditAffordances
                            ? () => toggleChannelHidden(channel.id)
                            : undefined
                        }
                      />
                    </div>
                  )
                })}
              </div>
            </>
          )
        )}

        {tab === 'playlists' && (
          <PlaylistsPlaceholder />
        )}

        {tab === 'feed' && (
          <FeedTab
            channels={visibleChannels}
            videos={videos}
            onPlay={(videoId, channelId) => send({ type: 'playVideo', payload: { videoId, source: 'channel', contextId: channelId } })}
          />
        )}
      </div>
    </div>
  )
}

// ─── Tab nav button ───────────────────────────────────────────────────────────
function TabBtn({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  const [hover, setHover] = useState(false)
  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        height: 38,
        padding: '0 14px',
        background: 'transparent',
        border: 'none',
        color: active ? 'var(--text-primary)' : hover ? 'var(--text-primary)' : 'var(--text-secondary)',
        fontSize: 14,
        fontWeight: 600,
        cursor: 'pointer',
        outline: 'none',
        transition: 'color 160ms ease',
      }}
    >
      {label}
      {/* Active underline */}
      <div style={{
        position: 'absolute',
        bottom: -1,
        left: 12,
        right: 12,
        height: 2,
        background: active ? 'var(--accent)' : 'transparent',
        borderRadius: 2,
        transition: 'background 200ms ease',
      }} />
    </button>
  )
}

// ─── Sort dropdown ────────────────────────────────────────────────────────────
const SORT_LABELS: Record<ChannelSort, string> = {
  custom: 'Custom',
  name:   'Name',
  recent: 'Recently updated',
}
function SortDropdown({ value, onChange }: { value: ChannelSort; onChange: (s: ChannelSort) => void }) {
  return (
    <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--text-secondary)' }}>
      <span>Sort:</span>
      <select
        value={value}
        onChange={e => onChange(e.target.value as ChannelSort)}
        style={{
          background: 'rgba(255,255,255,0.05)',
          border: '1px solid rgba(255,255,255,0.12)',
          borderRadius: 8,
          color: 'var(--text-primary)',
          fontSize: 13,
          fontWeight: 600,
          padding: '6px 10px',
          cursor: 'pointer',
          outline: 'none',
        }}
      >
        {(Object.keys(SORT_LABELS) as ChannelSort[]).map(s => (
          <option key={s} value={s}>{SORT_LABELS[s]}</option>
        ))}
      </select>
    </label>
  )
}

// ─── Autoplay picker (edit layer) ─────────────────────────────────────────────
// Per-profile channel-playback behaviour. Adults set this in the edit
// layer; it governs what happens when a channel-launched video ends.
const AUTOPLAY_LABELS: Record<string, string> = {
  exit:       'Off — back to channel',
  sequential: 'Play next',
  repeatOne:  'Repeat one',
  random:     'Shuffle',
}
function AutoplayPicker({ value, onChange }: { value: string; onChange: (mode: string) => void }) {
  const safe = AUTOPLAY_LABELS[value] ? value : 'exit'
  return (
    <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--text-secondary)' }}>
      <span>Autoplay:</span>
      <select
        value={safe}
        onChange={e => onChange(e.target.value)}
        style={{
          background: 'rgba(255,255,255,0.05)',
          border: '1px solid rgba(255,255,255,0.12)',
          borderRadius: 8,
          color: 'var(--text-primary)',
          fontSize: 13,
          fontWeight: 600,
          padding: '6px 10px',
          cursor: 'pointer',
          outline: 'none',
        }}
      >
        {Object.keys(AUTOPLAY_LABELS).map(m => (
          <option key={m} value={m}>{AUTOPLAY_LABELS[m]}</option>
        ))}
      </select>
    </label>
  )
}

// ─── Empty channels state ─────────────────────────────────────────────────────
function EmptyChannelsState({ appMode, onOpenAdmin }: { appMode: string; onOpenAdmin: () => void }) {
  return (
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
      <h2 style={{ fontSize: 36, color: 'var(--text-primary)' }}>No channels yet</h2>
      <p style={{ color: 'var(--text-secondary)', fontSize: 20, textAlign: 'center', maxWidth: 380 }}>
        {appMode === 'editor'
          ? 'Head to Admin to create channels and add videos.'
          : 'Ask a grown-up to add channels in Admin mode.'}
      </p>
      {appMode === 'editor' && (
        <button className="lt-btn-primary" onClick={onOpenAdmin} style={{ marginTop: 16 }}>
          Open Admin
        </button>
      )}
    </div>
  )
}

// ─── Playlists placeholder ────────────────────────────────────────────────────
function PlaylistsPlaceholder() {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      gap: 14,
      textAlign: 'center',
    }}>
      <div style={{
        width: 96,
        height: 96,
        borderRadius: 28,
        background: 'linear-gradient(135deg, rgba(155,93,229,0.18) 0%, rgba(96,165,250,0.12) 100%)',
        border: '1px solid rgba(155,93,229,0.25)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <svg width="44" height="44" viewBox="0 0 24 24" fill="none">
          <path d="M3 6h12M3 12h12M3 18h8" stroke="var(--accent)" strokeWidth="2" strokeLinecap="round" />
          <path d="M18 14v8M14 18h8" stroke="var(--accent)" strokeWidth="2" strokeLinecap="round" />
        </svg>
      </div>
      <h2 style={{ fontSize: 28, color: 'var(--text-primary)' }}>Playlists coming soon</h2>
      <p style={{ fontSize: 16, color: 'var(--text-secondary)', maxWidth: 380 }}>
        Soon you'll be able to queue up videos to watch in a row and curate
        named playlists for each profile.
      </p>
    </div>
  )
}

// ─── Feed tab ─────────────────────────────────────────────────────────────────
// Chronological cross-channel river. All ready videos from the active
// profile's visible channels, newest-downloaded first. Rendered as a
// vertical list of compact rows so dozens of items fit on screen.
function FeedTab({
  channels, videos, onPlay,
}: {
  channels: Channel[]
  videos: Record<string, Video[]>
  onPlay: (videoId: string, channelId: string) => void
}) {
  const rows = useMemo(() => {
    const all: { video: Video; channel: Channel; ts: number }[] = []
    for (const ch of channels) {
      for (const v of (videos[ch.id] ?? [])) {
        if (v.downloadState !== 'ready') continue
        const ts = v.downloadedAt ? Date.parse(v.downloadedAt) : 0
        all.push({ video: v, channel: ch, ts })
      }
    }
    all.sort((a, b) => b.ts - a.ts)
    return all
  }, [channels, videos])

  if (rows.length === 0) {
    return (
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        height: '100%',
        gap: 14,
        textAlign: 'center',
      }}>
        <span style={{ fontSize: 48 }}>📭</span>
        <h2 style={{ fontSize: 24 }}>No videos yet</h2>
        <p style={{ fontSize: 16, color: 'var(--text-secondary)' }}>
          Downloads will appear here as they finish.
        </p>
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, maxWidth: 920 }}>
      <h2 style={{ fontSize: 28, fontWeight: 800, marginBottom: 12 }}>Recently added</h2>
      {rows.map(({ video, channel, ts }) => (
        <FeedRow key={video.id} video={video} channel={channel} ts={ts} onPlay={() => onPlay(video.id, channel.id)} />
      ))}
    </div>
  )
}

function FeedRow({
  video, channel, ts, onPlay,
}: {
  video: Video
  channel: Channel
  ts: number
  onPlay: () => void
}) {
  const [hover, setHover] = useState(false)
  return (
    <button
      type="button"
      onClick={onPlay}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex',
        gap: 14,
        padding: 10,
        borderRadius: 14,
        background: hover ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.02)',
        border: `1px solid ${hover ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.06)'}`,
        textAlign: 'left',
        cursor: 'pointer',
        transition: 'background 160ms ease, border-color 160ms ease, transform 160ms ease',
        transform: hover ? 'translateX(2px)' : 'translateX(0)',
      }}
    >
      <div style={{
        position: 'relative',
        width: 168,
        height: 94,
        borderRadius: 10,
        overflow: 'hidden',
        flexShrink: 0,
        background: 'rgba(255,255,255,0.04)',
      }}>
        {video.thumbnailPath && (
          <Thumb
            video={video}
            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
          />
        )}
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 6 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: 'var(--text-tertiary)' }}>
          {channel.emoji && <span style={{ fontSize: 14 }}>{channel.emoji}</span>}
          <span style={{ fontWeight: 600 }}>{channel.displayName}</span>
          {ts > 0 && (
            <>
              <span aria-hidden style={{ opacity: 0.4 }}>·</span>
              <span>{relativeTime(ts)}</span>
            </>
          )}
        </div>
        <div
          className="line-clamp-2"
          style={{
            fontSize: 16,
            fontWeight: 600,
            color: 'var(--text-primary)',
            letterSpacing: '-0.01em',
            lineHeight: 1.3,
          }}
        >
          {video.title}
        </div>
      </div>
    </button>
  )
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function channelActivity(c: Channel, videos: Record<string, Video[]>): number {
  let latest = c.lastSyncedAt ? Date.parse(c.lastSyncedAt) : 0
  for (const v of (videos[c.id] ?? [])) {
    const t = v.downloadedAt ? Date.parse(v.downloadedAt) : 0
    if (t > latest) latest = t
  }
  return latest
}

function relativeTime(ts: number): string {
  const diff = Date.now() - ts
  const m = Math.floor(diff / 60_000)
  if (m < 1) return 'just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.floor(h / 24)
  if (d < 7) return `${d}d ago`
  const w = Math.floor(d / 7)
  if (w < 5) return `${w}w ago`
  const mo = Math.floor(d / 30)
  return `${mo}mo ago`
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

// ─── Editing banner — sticky chip indicating who's being edited ──────────────
function EditingBanner({ profile }: { profile: Profile }) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '6px 12px 6px 8px',
      borderRadius: 99,
      background: 'rgba(155,93,229,0.16)',
      border: '1px solid rgba(155,93,229,0.36)',
      color: 'var(--accent)',
      fontSize: 13,
      fontWeight: 600,
      letterSpacing: '-0.005em',
    }}>
      <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
        <path d="M10 1.5L12.5 4L4.5 12H2V9.5L10 1.5Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" fill="none" />
      </svg>
      <span>Editing {profile.name}'s library</span>
    </div>
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
