import { useState, useMemo, useEffect, useRef, useCallback } from 'react'
import { useAppStore } from '../store'
import VideoCard, { Thumb } from '../components/VideoCard'
import type { Video } from '../types'
import { thumbUrl } from '../utils'

// Banner collapse tuning — full banner at scrollTop=0, fully gone by
// COLLAPSE_DISTANCE. Easing is applied to the raw progress so the early
// scroll feels grippy and the tail eases out, matching YouTube's collapse.
const BANNER_HEIGHT = 300
const COLLAPSE_DISTANCE = 220
const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3)

export default function Channel() {
  const { state, nav, navigateTo, send } = useAppStore()
  const { channels, videos, appMode, activeDownload } = state
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [showAddVideos, setShowAddVideos] = useState(false)
  const [urlInput, setUrlInput] = useState('')
  const [adding, setAdding] = useState(false)
  const [pageSize, setPageSize] = useState<number>(() => {
    const saved = localStorage.getItem('lt-page-size')
    return saved ? Number(saved) : 24
  })
  const [currentPage, setCurrentPage] = useState(0)
  const [searchQuery, setSearchQuery] = useState('')
  const scrollRef = useRef<HTMLDivElement>(null)

  // Scroll-driven banner collapse. We track scrollTop on the content scroll
  // container and derive a 0→1 progress that drives the banner height/opacity
  // and the top-bar elevation shadow. rAF coalesces fast scroll events into
  // at most one state update per frame.
  const [scrollY, setScrollY] = useState(0)
  const rafRef = useRef<number | null>(null)
  const handleScroll = useCallback((e: React.UIEvent<HTMLDivElement>) => {
    const y = e.currentTarget.scrollTop
    if (rafRef.current !== null) return
    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = null
      setScrollY(y)
    })
  }, [])
  useEffect(() => () => {
    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
  }, [])

  // Reset to first page whenever the channel changes or search changes
  useEffect(() => { setCurrentPage(0) }, [nav.channelId, searchQuery])

  // Scroll content area back to top on every page change
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0, behavior: 'instant' })
    setScrollY(0)
  }, [currentPage])

  // Resetting scroll position when the channel changes too — otherwise a
  // user scrolled deep in one channel keeps the banner collapsed when they
  // navigate to another channel that may have no banner at all.
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0, behavior: 'instant' })
    setScrollY(0)
  }, [nav.channelId])

  // Ten-foot UX: wheel/trackpad scrolling should work anywhere on the
  // channel screen, not just when the cursor happens to be over the video
  // grid. We forward any wheel event whose target isn't already inside
  // scrollRef to the scroll container. Without this, scrolling while the
  // cursor is over the banner, header, or search bar does nothing — which
  // is exactly where the cursor is when the user *starts* to scroll down.
  const handleScreenWheel = useCallback((e: React.WheelEvent<HTMLDivElement>) => {
    const container = scrollRef.current
    if (!container) return
    if (container.contains(e.target as Node)) return  // already over scroll area
    container.scrollBy({ top: e.deltaY, left: e.deltaX, behavior: 'auto' })
  }, [])

  const channel = channels.find(c => c.id === nav.channelId)
  const channelVideos = (nav.channelId ? videos[nav.channelId] : []) ?? []
  const isEditor = appMode === 'editor'

  const sortedVideos = useMemo(
    () => [...channelVideos].sort((a, b) => a.sortOrder - b.sortOrder),
    [channelVideos]
  )
  const isSyncing = channel ? (state.syncingChannelIds ?? []).includes(channel.id) : false

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

  // H9 fix: Keep loading state visible until a stateUpdate event arrives from
  // Swift confirming the videos were processed. Use a timeout fallback so the
  // UI is never stuck if Swift fails to respond.
  const handleAddVideos = () => {
    const urls = urlInput
      .split('\n')
      .map(u => u.trim())
      .filter(u => u.length > 0)
    if (urls.length === 0) return
    setAdding(true)
    send({ type: 'addVideoURLs', payload: { channelId: channel.id, urls } })
    setUrlInput('')
    // Reset after a reasonable timeout — the stateUpdate event from Swift
    // will update the video list. This timeout is a fallback.
    setTimeout(() => {
      setAdding(false)
      setShowAddVideos(false)
    }, 2000)
  }

  const handleDeleteVideo = (videoId: string) => {
    send({ type: 'deleteVideo', payload: { videoId } })
  }

  const handleRetry = (videoId: string) => {
    send({ type: 'retryDownload', payload: { videoId } })
  }

  const handlePageSize = (size: number) => {
    setPageSize(size)
    setCurrentPage(0)
    localStorage.setItem('lt-page-size', String(size))
  }

  const readyCount = useMemo(
    () => sortedVideos.filter(v => v.downloadState === 'ready').length,
    [sortedVideos]
  )

  const filteredVideos = useMemo(() => {
    const q = searchQuery.trim().toLowerCase()
    if (!q) return sortedVideos
    return sortedVideos.filter(v => v.title.toLowerCase().includes(q))
  }, [sortedVideos, searchQuery])

  const totalPages = Math.ceil(filteredVideos.length / pageSize)
  const pagedVideos = useMemo(
    () => filteredVideos.slice(currentPage * pageSize, (currentPage + 1) * pageSize),
    [filteredVideos, currentPage, pageSize]
  )

  // Derived collapse progress for the banner + top bar. Eased so the early
  // scroll feels grippy. Only meaningful when a banner is present.
  const hasBanner = !!channel.bannerPath
  const rawProgress = hasBanner ? Math.min(1, Math.max(0, scrollY / COLLAPSE_DISTANCE)) : 0
  const collapseProgress = easeOutCubic(rawProgress)
  const bannerHeight = BANNER_HEIGHT * (1 - collapseProgress)
  const bannerOpacity = 1 - collapseProgress
  // Subtle channel-name shrink + shadow on the top bar once banner is mostly gone
  const channelTitleSize = 28 - 6 * collapseProgress
  const topBarShadowAlpha = 0.35 * collapseProgress

  // Pick a random thumbnail from this channel to use as the *initial* ambient
  // background. The scroll-driven crossfade below takes over once the user
  // starts scrolling.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const initialBgThumb = useMemo(() => {
    const withThumb = sortedVideos.filter(v => v.thumbnailPath)
    if (withThumb.length === 0) return null
    return withThumb[Math.floor(Math.random() * withThumb.length)]
  }, [channel.id, sortedVideos.length > 0])

  // ── Ambient background: two-slot crossfade ────────────────────────────────
  // We keep two background slots (a, b) and toggle which one is rendered at
  // opacity 1 vs 0. Swapping the *inactive* slot to a new video and then
  // flipping activeKey gives us a clean opacity crossfade without ever
  // reloading the currently-visible image — which would force the browser to
  // re-rasterize the full-screen blur stack mid-fade.
  //
  // The dominant visible video is picked via IntersectionObserver (cheap
  // native API) and only committed after a 350 ms trailing-edge debounce so
  // a fast scroll past 20 cards triggers one crossfade, not twenty.
  type BgSlots = { a: Video | null; b: Video | null; active: 'a' | 'b' }
  const [bgSlots, setBgSlots] = useState<BgSlots>({ a: null, b: null, active: 'a' })

  // Seed the active slot with the initial random pick when entering the channel.
  useEffect(() => {
    setBgSlots({ a: initialBgThumb, b: null, active: 'a' })
  }, [channel.id, initialBgThumb])

  const swapBg = useCallback((next: Video) => {
    setBgSlots(prev => {
      const current = prev.active === 'a' ? prev.a : prev.b
      if (current?.id === next.id) return prev
      // Write the new video into the *inactive* slot, then flip active so
      // the new slot fades in while the old one fades out. The image that
      // *was* on screen is left in place until its opacity finishes
      // transitioning, so no re-rasterization of a visible blur layer.
      return prev.active === 'a'
        ? { a: prev.a, b: next, active: 'b' }
        : { a: next, b: prev.b, active: 'a' }
    })
  }, [])

  // IntersectionObserver: watch all card wrappers, pick the middle visible
  // one and swap the bg AS the user scrolls — not after. We use a
  // leading-edge rate limit (one swap per fade duration) so back-to-back
  // intersection events during a fast scroll don't queue up overlapping
  // crossfades. A tiny trailing-edge settle (80 ms after the last
  // intersection event) guarantees the bg lands on the true center video
  // when the user stops scrolling — without the heavy trailing debounce
  // that previously made the bg only update after motion stopped.
  const visibleIdsRef = useRef<Set<string>>(new Set())
  const settleTimerRef = useRef<number | null>(null)
  const lastSwapAtRef = useRef(0)

  // Compute and commit the dominant visible video, respecting the rate limit.
  // `force` bypasses the rate limit so the trailing settle always fires.
  const commitDominant = useCallback((force: boolean) => {
    const now = performance.now()
    if (!force && now - lastSwapAtRef.current < BG_FADE_MS) return
    const inOrder = pagedVideos
      .filter(v => visibleIdsRef.current.has(v.id) && v.thumbnailPath)
    if (inOrder.length === 0) return
    const mid = inOrder[Math.floor(inOrder.length / 2)]
    lastSwapAtRef.current = now
    swapBg(mid)
  }, [pagedVideos, swapBg])

  useEffect(() => {
    const grid = scrollRef.current?.querySelector('[data-video-grid]')
    if (!grid) return
    const cards = grid.querySelectorAll<HTMLElement>('[data-video-id]')
    if (cards.length === 0) return

    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        const id = (entry.target as HTMLElement).dataset.videoId
        if (!id) continue
        if (entry.isIntersecting) visibleIdsRef.current.add(id)
        else visibleIdsRef.current.delete(id)
      }
      // Leading-edge: swap right now if enough time has passed.
      commitDominant(false)
      // Trailing-edge settle: short timer (80 ms) so when scroll stops,
      // we re-pick the dominant once even if the rate-limit blocked the
      // last live update. Bypasses the rate limit (force=true).
      if (settleTimerRef.current !== null) {
        window.clearTimeout(settleTimerRef.current)
      }
      settleTimerRef.current = window.setTimeout(() => {
        settleTimerRef.current = null
        commitDominant(true)
      }, 80)
    }, {
      root: scrollRef.current,
      // Multiple thresholds = more frequent callbacks as cards drift across
      // the viewport, so the dominant pick can update during the scroll
      // rather than only when a card fully crosses the half-visible line.
      threshold: [0, 0.25, 0.5, 0.75, 1],
    })

    cards.forEach(el => observer.observe(el))
    return () => {
      observer.disconnect()
      visibleIdsRef.current.clear()
      if (settleTimerRef.current !== null) {
        window.clearTimeout(settleTimerRef.current)
        settleTimerRef.current = null
      }
    }
  }, [pagedVideos, commitDominant])

  return (
    <div className="screen-slide-in" onWheel={handleScreenWheel} style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      position: 'relative',
      overflow: 'hidden',
      background: 'var(--bg)',
    }}>
      {/* ── Ambient background (two-slot crossfade) ───────────────────────── */}
      {(bgSlots.a || bgSlots.b) && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 0, pointerEvents: 'none' }}>
          <BgBlurStack video={bgSlots.a} visible={bgSlots.active === 'a'} />
          <BgBlurStack video={bgSlots.b} visible={bgSlots.active === 'b'} />
          {/* Dark scrim — kept outside the crossfade so legibility is constant. */}
          <div style={{
            position: 'absolute',
            inset: 0,
            background: 'rgba(13,13,15,0.68)',
          }} />
          {/* Monochromatic pixel noise — breaks the blur's banding at 10%. */}
          <div style={{
            position: 'absolute',
            inset: 0,
            opacity: 0.10,
            backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='1' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
            backgroundRepeat: 'repeat',
            backgroundSize: '96px 96px',
          }} />
        </div>
      )}

      {/* ── Banner hero ────────────────────────────────────────────────────── */}
      {hasBanner ? (
        <div style={{
          position: 'relative',
          zIndex: 1,
          width: '100%',
          height: bannerHeight,
          opacity: bannerOpacity,
          flexShrink: 0,
          overflow: 'hidden',
          // No CSS transition on height — we drive it per-frame from the
          // scroll handler so it tracks the scroll velocity exactly. Adding
          // a transition here would feel laggy.
          willChange: 'height, opacity',
        }}>
          <img
            src={channel.bannerPath}
            alt=""
            style={{
              position: 'absolute',
              inset: 0,
              width: '100%',
              // Use the unscaled banner height so the image doesn't rescale as
              // the container shrinks — it just clips upward, matching how
              // YouTube parallaxes the banner away.
              height: BANNER_HEIGHT,
              objectFit: 'cover',
              filter: 'brightness(0.7) saturate(1.1)',
              transform: `translateY(${-collapseProgress * BANNER_HEIGHT * 0.35}px)`,
            }}
            onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
          />
          {/* Bottom gradient scrim so content below stays readable */}
          <div style={{
            position: 'absolute',
            inset: 0,
            background: 'linear-gradient(to bottom, transparent 40%, rgba(13,13,15,0.9) 100%)',
          }} />
        </div>
      ) : null}

      {/* Top bar — sticky-ish: stays put while content scrolls underneath.
          Gains a subtle drop shadow once the banner has collapsed to give
          the compact header a sense of elevation over the scrolling list. */}
      <div style={{
        position: 'relative',
        zIndex: 2,
        display: 'flex',
        alignItems: 'center',
        padding: '0 40px',
        height: 80,
        background: 'linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.04) 100%)',
        backgroundColor: initialBgThumb ? 'rgba(13,13,15,0.75)' : 'rgba(13,13,15,0.88)',
        backdropFilter: 'blur(28px) saturate(200%)',
        WebkitBackdropFilter: 'blur(28px) saturate(200%)',
        borderBottom: '0.5px solid rgba(255,255,255,0.1)',
        boxShadow: topBarShadowAlpha > 0
          ? `0 6px 22px rgba(0,0,0,${topBarShadowAlpha})`
          : 'none',
        transition: 'box-shadow 180ms ease-out',
        flexShrink: 0,
        gap: 12,
      }}>
        {/* Back button */}
        <button
          className="lt-btn-ghost"
          onClick={() => navigateTo({ screen: 'library' })}
          style={{ padding: '6px 10px', gap: 6, color: 'var(--text-secondary)' }}
        >
          <svg width="20" height="20" viewBox="0 0 16 16" fill="none">
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
            <h1 style={{
              fontSize: channelTitleSize,
              fontWeight: 800,
              letterSpacing: '-0.02em',
              // No transition — driven per-frame alongside banner collapse so
              // it tracks scroll velocity.
            }}>
              {channel.displayName}
            </h1>
          </div>
          <div style={{
            padding: '4px 14px',
            borderRadius: 99,
            background: 'linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.04) 100%)',
            border: '0.5px solid rgba(255,255,255,0.13)',
            backdropFilter: 'blur(16px) saturate(160%)',
            WebkitBackdropFilter: 'blur(16px) saturate(160%)',
            fontSize: 16,
            color: 'var(--text-secondary)',
            marginLeft: 4,
          }}>
            {readyCount}/{sortedVideos.length}
          </div>
        </div>

        {/* Right controls */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {/* Syncing indicator — shown in any mode while sync is running */}
          {isSyncing && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '5px 10px', borderRadius: 8, background: 'rgba(155,93,229,0.1)', border: '0.5px solid rgba(155,93,229,0.3)' }}>
              <svg className="spinner" width="12" height="12" viewBox="0 0 12 12" fill="none">
                <circle cx="6" cy="6" r="4.5" stroke="rgba(155,93,229,0.3)" strokeWidth="1.5" />
                <path d="M6 1.5A4.5 4.5 0 0 1 10.5 6" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              <span style={{ fontSize: 16, color: 'var(--accent)', fontWeight: 500 }}>Syncing…</span>
            </div>
          )}

          {/* Sync button — source channels only, editor mode */}
          {isEditor && channel?.type === 'source' && !isSyncing && (
            <button
              className="lt-btn-secondary"
              onClick={() => send({ type: 'syncChannel', payload: { channelId: channel.id } })}
              style={{ padding: '6px 12px', fontSize: 16 }}
              title="Fetch latest videos from YouTube"
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M1.5 6.5A5 5 0 0 1 11 3.5M11.5 6.5A5 5 0 0 1 2 9.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                <path d="M9 1.5L11 3.5L9 5.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M4 7.5L2 9.5L4 11.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Sync
            </button>
          )}

          {/* Upload banner (editor) */}
          {isEditor && (
            <button
              className="lt-btn-secondary"
              onClick={() => send({ type: 'uploadChannelBanner', payload: { channelId: channel.id } })}
              style={{ padding: '6px 12px', fontSize: 16 }}
              title={channel.type === 'source' ? 'Override banner with custom image' : 'Upload channel banner'}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M6.5 9V3M6.5 3L4 5.5M6.5 3L9 5.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M2 10.5H11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              Banner
            </button>
          )}

          {/* Add videos (editor) */}
          {isEditor && (
            <button
              className="lt-btn-primary"
              onClick={() => setShowAddVideos(true)}
              style={{ padding: '6px 12px', fontSize: 16 }}
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
              style={{ padding: '6px 12px', fontSize: 16 }}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M2 3.5H11M4.5 3.5V2.5A1 1 0 0 1 5.5 1.5H7.5A1 1 0 0 1 8.5 2.5V3.5M5 6V10M8 6V10" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M3 3.5L3.5 11H9.5L10 3.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Delete
            </button>
          )}

          {/* Page size selector — editor only */}
          {isEditor && (
            <div style={{
              display: 'flex',
              background: 'linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.04) 100%)',
              border: '0.5px solid rgba(255,255,255,0.13)',
              backdropFilter: 'blur(16px) saturate(160%)',
              WebkitBackdropFilter: 'blur(16px) saturate(160%)',
              borderRadius: 8,
              padding: 2,
              gap: 1,
            }}>
              {[16, 24, 36, 48].map(size => (
                <button
                  key={size}
                  onClick={() => handlePageSize(size)}
                  style={{
                    padding: '4px 9px',
                    borderRadius: 6,
                    border: 'none',
                    fontSize: 14,
                    fontWeight: 600,
                    cursor: 'pointer',
                    background: pageSize === size
                      ? 'linear-gradient(135deg, rgba(255,255,255,0.14) 0%, rgba(255,255,255,0.09) 100%)'
                      : 'transparent',
                    color: pageSize === size ? 'var(--text-primary)' : 'var(--text-tertiary)',
                    transition: 'all 140ms ease',
                  }}
                >
                  {size}
                </button>
              ))}
            </div>
          )}

          {/* View mode toggle */}
          <div style={{
            display: 'flex',
            background: 'linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.04) 100%)',
            border: '0.5px solid rgba(255,255,255,0.13)',
            backdropFilter: 'blur(16px) saturate(160%)',
            WebkitBackdropFilter: 'blur(16px) saturate(160%)',
            borderRadius: 8,
            padding: 2,
          }}>
            {(['grid', 'list'] as const).map(mode => (
              <button
                key={mode}
                className={`lt-view-toggle-btn${viewMode === mode ? ' active' : ''}`}
                onClick={() => setViewMode(mode)}
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

      {/* Search bar */}
      {sortedVideos.length > 0 && (
        <div style={{
          position: 'relative',
          zIndex: 1,
          padding: '12px 44px',
          flexShrink: 0,
          background: 'rgba(13,13,15,0.55)',
          backdropFilter: 'blur(16px)',
          WebkitBackdropFilter: 'blur(16px)',
          borderBottom: '0.5px solid rgba(255,255,255,0.07)',
        }}>
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            background: 'rgba(255,255,255,0.06)',
            border: `0.5px solid ${searchQuery ? 'rgba(155,93,229,0.5)' : 'rgba(255,255,255,0.1)'}`,
            borderRadius: 10,
            padding: '8px 14px',
            maxWidth: 480,
            transition: 'border-color 150ms ease',
          }}>
            <svg width="15" height="15" viewBox="0 0 15 15" fill="none" style={{ flexShrink: 0, color: 'var(--text-tertiary)' }}>
              <circle cx="6.5" cy="6.5" r="5" stroke="currentColor" strokeWidth="1.4" />
              <path d="M10.5 10.5L13.5 13.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
            </svg>
            <input
              type="text"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search videos…"
              style={{
                flex: 1,
                background: 'none',
                border: 'none',
                outline: 'none',
                fontSize: 15,
                color: 'var(--text-primary)',
                caretColor: 'var(--accent)',
              }}
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery('')}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-tertiary)',
                  padding: 2,
                  display: 'flex',
                  alignItems: 'center',
                }}
              >
                <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                  <path d="M2 2L11 11M11 2L2 11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                </svg>
              </button>
            )}
          </div>
          {searchQuery && (
            <p style={{ margin: '6px 0 0', fontSize: 13, color: 'var(--text-tertiary)' }}>
              {filteredVideos.length} result{filteredVideos.length !== 1 ? 's' : ''} for "{searchQuery}"
            </p>
          )}
        </div>
      )}

      {/* Content */}
      <div ref={scrollRef} onScroll={handleScroll} style={{
        position: 'relative',
        zIndex: 1,
        flex: 1,
        overflowY: 'auto',
        padding: '44px',
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
              width: 96,
              height: 96,
              borderRadius: 26,
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <svg width="44" height="44" viewBox="0 0 28 28" fill="none">
                <rect x="2" y="4" width="24" height="20" rx="3.5" stroke="var(--text-tertiary)" strokeWidth="1.5" fill="none" />
                <polygon points="11,10 21,14 11,18" fill="var(--text-tertiary)" />
              </svg>
            </div>
            <h2 style={{ fontSize: 30 }}>No videos in {channel.displayName}</h2>
            <p style={{ fontSize: 18, color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 380 }}>
              {isSyncing
                ? 'Fetching video list from YouTube…'
                : channel.type === 'source' && isEditor
                  ? 'Hit Sync to pull the latest videos from this YouTube channel, or add individual URLs below.'
                  : channel.type === 'source'
                    ? 'Videos will appear here once synced.'
                    : isEditor
                      ? 'Add YouTube video URLs to start downloading.'
                      : 'Videos will appear here when they\'re added.'}
            </p>
            {isEditor && channel.type === 'source' && !isSyncing && (
              <button
                className="lt-btn-primary"
                onClick={() => send({ type: 'syncChannel', payload: { channelId: channel.id } })}
                style={{ marginTop: 4, display: 'flex', alignItems: 'center', gap: 6 }}
              >
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M1.5 7A5.5 5.5 0 0 1 12 4M12.5 7A5.5 5.5 0 0 1 2 10" stroke="white" strokeWidth="1.6" strokeLinecap="round" />
                  <path d="M10 2L12 4L10 6" stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  <path d="M4 8L2 10L4 12" stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                Sync Channel
              </button>
            )}
            {isEditor && channel.type !== 'source' && (
              <button
                className="lt-btn-primary"
                onClick={() => setShowAddVideos(true)}
                style={{ marginTop: 4 }}
              >
                Add Videos
              </button>
            )}
          </div>
        ) : filteredVideos.length === 0 ? (
          <div style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            height: '100%',
            gap: 12,
          }}>
            <div style={{
              width: 80,
              height: 80,
              borderRadius: 22,
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <svg width="36" height="36" viewBox="0 0 15 15" fill="none">
                <circle cx="6.5" cy="6.5" r="5" stroke="var(--text-tertiary)" strokeWidth="1.2" />
                <path d="M10.5 10.5L13.5 13.5" stroke="var(--text-tertiary)" strokeWidth="1.2" strokeLinecap="round" />
              </svg>
            </div>
            <h2 style={{ fontSize: 24 }}>No videos found</h2>
            <p style={{ fontSize: 16, color: 'var(--text-secondary)' }}>
              Nothing matches "{searchQuery}"
            </p>
            <button className="lt-btn-secondary" onClick={() => setSearchQuery('')}>
              Clear Search
            </button>
          </div>
        ) : viewMode === 'grid' ? (
          <>
            <div data-video-grid style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
              gap: 22,
            }}>
              {pagedVideos.map(video => (
                <div key={video.id} data-video-id={video.id} className="reveal">
                  <VideoCard
                    video={video}
                    isEditorMode={isEditor}
                    isActiveDownload={activeDownload?.videoId === video.id}
                    onPlay={() => send({ type: 'playVideo', payload: { videoId: video.id } })}
                    onDelete={isEditor ? () => handleDeleteVideo(video.id) : undefined}
                    onRetry={() => handleRetry(video.id)}
                  />
                </div>
              ))}
            </div>

            {/* Pagination */}
            {totalPages > 1 && (
              <div style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 10,
                marginTop: 44,
                paddingBottom: 8,
              }}>
                <button
                  className="lt-btn-secondary"
                  onClick={() => setCurrentPage(p => Math.max(0, p - 1))}
                  disabled={currentPage === 0}
                  style={{ padding: '8px 20px', fontSize: 16, opacity: currentPage === 0 ? 0.35 : 1 }}
                >
                  ← Prev
                </button>
                <span style={{ fontSize: 16, color: 'var(--text-secondary)', minWidth: 100, textAlign: 'center' }}>
                  {currentPage + 1} / {totalPages}
                </span>
                <button
                  className="lt-btn-secondary"
                  onClick={() => setCurrentPage(p => Math.min(totalPages - 1, p + 1))}
                  disabled={currentPage === totalPages - 1}
                  style={{ padding: '8px 20px', fontSize: 16, opacity: currentPage === totalPages - 1 ? 0.35 : 1 }}
                >
                  Next →
                </button>
              </div>
            )}
          </>
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
        <div className="modal-backdrop" role="presentation">
          <div className="modal-panel" role="dialog" aria-modal="true" aria-label="Confirm delete channel" style={{ width: 480, padding: '44px 40px' }}>
            <div style={{
              width: 72,
              height: 72,
              borderRadius: 20,
              background: 'rgba(248,113,113,0.1)',
              border: '1px solid rgba(248,113,113,0.25)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: 16,
            }}>
              <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
                <path d="M3 6H21M8 6V4H16V6M10 11V17M14 11V17" stroke="#f87171" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M5 6L6 20H18L19 6" stroke="#f87171" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <h2 style={{ fontSize: 26, marginBottom: 8 }}>Delete "{channel.displayName}"?</h2>
            <p style={{ fontSize: 18, color: 'var(--text-secondary)', marginBottom: 24 }}>
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
        <div className="modal-backdrop" role="presentation">
          <div className="modal-panel" role="dialog" aria-modal="true" aria-label="Add videos" style={{ width: 600, padding: '40px' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
              <div>
                <h2 style={{ fontSize: 26, marginBottom: 4 }}>Add Videos</h2>
                <p style={{ fontSize: 18, color: 'var(--text-secondary)' }}>
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
              style={{ fontFamily: 'ui-monospace, monospace', fontSize: 17 }}
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

// ─── Ambient blur stack ──────────────────────────────────────────────────────
// One layer of the two-slot crossfade. Renders two stacked blurs (primary +
// screen-blend overlay) wrapped in an opacity-transitioned div so the *slot*
// can fade as a unit. willChange hints the compositor to keep a separate
// layer so the blur output is cached between swaps. pointer-events stay off
// so nothing intercepts grid interactions.
//
// 400 ms strikes a balance: short enough that consecutive scroll-driven
// swaps don't visibly overlap (we rate-limit at this same duration), long
// enough to feel like a deliberate ambient transition rather than a snap.
const BG_FADE_MS = 400
function BgBlurStack({ video, visible }: { video: Video | null; visible: boolean }) {
  if (!video) return null
  return (
    <div style={{
      position: 'absolute',
      inset: 0,
      opacity: visible ? 1 : 0,
      transition: `opacity ${BG_FADE_MS}ms ease`,
      pointerEvents: 'none',
      willChange: 'opacity',
    }}>
      {/* Layer 1 — primary blur */}
      <Thumb
        video={video}
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          filter: 'blur(64px) saturate(200%) contrast(1.12) brightness(0.85)',
          opacity: 0.52,
          transform: 'scale(1.3)',
          transformOrigin: 'center',
        }}
      />
      {/* Layer 2 — screen-blend overlay, breaks the primary's banding */}
      <Thumb
        video={video}
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          filter: 'blur(40px) saturate(240%) brightness(1.15) hue-rotate(22deg)',
          opacity: 0.18,
          transform: 'scale(1.3) rotate(180deg)',
          transformOrigin: 'center',
          mixBlendMode: 'screen',
        }}
      />
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
  const [deleteBtnHovered, setDeleteBtnHovered] = useState(false)
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
        transition: 'background 140ms cubic-bezier(0.89,0,0.14,1)',
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
          <Thumb
            video={video}
            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
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
            className="lt-btn-retry"
            onClick={(e) => { e.stopPropagation(); onRetry?.() }}
          >
            Retry
          </button>
        )}
        {isEditorMode && onDelete && (
          <button
            onMouseEnter={() => setDeleteBtnHovered(true)}
            onMouseLeave={() => setDeleteBtnHovered(false)}
            onClick={(e) => { e.stopPropagation(); onDelete() }}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 26,
              height: 26,
              borderRadius: 6,
              border: `1px solid ${deleteBtnHovered ? 'rgba(248,113,113,0.55)' : 'rgba(248,113,113,0.3)'}`,
              background: deleteBtnHovered ? 'rgba(248,113,113,0.22)' : 'rgba(248,113,113,0.1)',
              color: 'var(--destructive)',
              cursor: 'pointer',
              opacity: hovered ? 1 : 0,
              transform: hovered ? 'scale(1)' : 'scale(0.8)',
              transition: 'opacity 140ms cubic-bezier(0.89,0,0.14,1), transform 180ms cubic-bezier(0.89,0,0.14,1), background 120ms cubic-bezier(0.89,0,0.14,1), border-color 120ms cubic-bezier(0.89,0,0.14,1)',
              pointerEvents: hovered ? 'auto' : 'none',
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

