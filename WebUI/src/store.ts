import React, {
  createContext,
  useContext,
  useEffect,
  useReducer,
  useCallback,
  useRef,
} from 'react'
import type { AppState, BridgeEvent, BridgeMessage, NavState, Video } from './types'
import { sendBridge, initBridge } from './bridge'

// ─── Default State ─────────────────────────────────────────────────────────
const defaultState: AppState = {
  channels: [],
  videos: {},
  appMode: 'viewer',
  isOnboarding: false,
  needsPINSetup: false,
  showPINEntry: false,
  settings: {
    downloadFolderPath: undefined,
    editorAutoLockMinutes: 15,
    downloadQuality: 'best',
  },
  dependencyStatus: {
    ytDlp: false,
    ffmpeg: false,
  },
  activeDownload: undefined,
  syncingChannelIds: [],
  isEditing: false,
  profiles: [],
  profileChannels: {},
  profileFavorites: {},
  profileHiddenChannels: {},
  playlists: [],
  playlistVideos: {},
  activeProfileId: undefined,
}

// ─── Store Shape ───────────────────────────────────────────────────────────
interface AppStore {
  state: AppState
  nav: NavState
  navigateTo: (nav: NavState) => void
  dispatch: (event: BridgeEvent) => void
  send: (msg: BridgeMessage) => void
  // Transient UI events (non-state)
  onFolderSelected?: (path: string) => void
  setOnFolderSelected: (fn: ((path: string) => void) | undefined) => void
  onPINValidated?: (valid: boolean) => void
  setOnPINValidated: (fn: ((valid: boolean) => void) | undefined) => void
}

// ─── State Reducer ─────────────────────────────────────────────────────────
type Action =
  | { kind: 'bridgeEvent'; event: BridgeEvent }
  | { kind: 'navigate'; nav: NavState }
  | { kind: 'setOnFolderSelected'; fn: ((path: string) => void) | undefined }
  | { kind: 'setOnPINValidated'; fn: ((valid: boolean) => void) | undefined }

interface FullState {
  app: AppState
  nav: NavState
  onFolderSelected?: (path: string) => void
  onPINValidated?: (valid: boolean) => void
}

function applyBridgeEvent(app: AppState, event: BridgeEvent): AppState {
  switch (event.type) {
    case 'stateUpdate': {
      const updated = { ...app, ...event.payload }
      // Merge nested objects carefully
      if (event.payload.settings) {
        updated.settings = { ...app.settings, ...event.payload.settings }
      }
      if (event.payload.dependencyStatus) {
        updated.dependencyStatus = { ...app.dependencyStatus, ...event.payload.dependencyStatus }
      }
      if (event.payload.videos) {
        updated.videos = { ...app.videos, ...event.payload.videos }
      }
      return updated
    }
    case 'downloadProgress': {
      const { videoId, progress } = event.payload
      const videos = { ...app.videos }
      let found = false
      for (const channelId of Object.keys(videos)) {
        const list = videos[channelId]
        const idx = list.findIndex(v => v.id === videoId)
        if (idx !== -1) {
          found = true
          const updated = [...list]
          updated[idx] = {
            ...updated[idx],
            downloadProgress: progress,
            downloadState: 'downloading',
          }
          videos[channelId] = updated
        }
      }
      if (!found) return app
      return {
        ...app,
        videos,
        activeDownload: app.activeDownload
          ? { ...app.activeDownload, progress, videoId }
          : { videoId, progress, title: '' },
      }
    }
    // Batch variant: apply multiple progress updates in a single state change.
    // Reduces 12 dispatches/sec (6 downloads × 2 ticks) to ≤1 per anim frame.
    case 'downloadProgressBatch': {
      const entries = event.payload
      const videos = { ...app.videos }
      let lastVideoId = ''
      let lastProgress = 0
      let anyFound = false
      for (const [videoId, progress] of Object.entries(entries)) {
        for (const channelId of Object.keys(videos)) {
          const list = videos[channelId]
          const idx = list.findIndex(v => v.id === videoId)
          if (idx !== -1) {
            anyFound = true
            // Only clone the channel array once per channel
            if (list === app.videos[channelId]) {
              videos[channelId] = [...list]
            }
            videos[channelId][idx] = {
              ...videos[channelId][idx],
              downloadProgress: progress,
              downloadState: 'downloading',
            }
            lastVideoId = videoId
            lastProgress = progress
          }
        }
      }
      if (!anyFound) return app
      return {
        ...app,
        videos,
        activeDownload: lastVideoId
          ? { videoId: lastVideoId, progress: lastProgress, title: app.activeDownload?.title ?? '' }
          : app.activeDownload,
      }
    }
    case 'downloadCompleted': {
      const { videoId } = event.payload
      const videos = { ...app.videos }
      for (const channelId of Object.keys(videos)) {
        const list = videos[channelId]
        const idx = list.findIndex(v => v.id === videoId)
        if (idx !== -1) {
          const updated = [...list]
          updated[idx] = {
            ...updated[idx],
            downloadProgress: 1,
            downloadState: 'ready',
          }
          videos[channelId] = updated
        }
      }
      const active =
        app.activeDownload?.videoId === videoId ? undefined : app.activeDownload
      return { ...app, videos, activeDownload: active }
    }
    case 'downloadError': {
      const { videoId, error } = event.payload
      const videos = { ...app.videos }
      for (const channelId of Object.keys(videos)) {
        const list = videos[channelId]
        const idx = list.findIndex(v => v.id === videoId)
        if (idx !== -1) {
          const updated = [...list]
          updated[idx] = {
            ...updated[idx],
            downloadState: 'error',
            downloadError: error,
          }
          videos[channelId] = updated
        }
      }
      return { ...app, videos }
    }
    // editorTimerTick removed with the auto-lock timer.
    // ── Targeted diff events ──────────────────────────────────────────────
    case 'channelUpserted': {
      const { channel } = event.payload
      const idx = app.channels.findIndex(c => c.id === channel.id)
      const channels = idx === -1
        ? [...app.channels, channel].sort((a, b) => a.sortOrder - b.sortOrder)
        : app.channels.map((c, i) => (i === idx ? channel : c))
      const videos = app.videos[channel.id] ? app.videos : { ...app.videos, [channel.id]: [] }
      return { ...app, channels, videos }
    }
    case 'channelRemoved': {
      const { channelId } = event.payload
      const channels = app.channels.filter(c => c.id !== channelId)
      const videos = { ...app.videos }
      delete videos[channelId]
      return { ...app, channels, videos }
    }
    case 'videosUpserted': {
      const { channelId, videos: incoming } = event.payload
      const existing = app.videos[channelId] ?? []
      const byId = new Map(existing.map(v => [v.id, v] as const))
      for (const v of incoming) byId.set(v.id, v)
      const merged = Array.from(byId.values()).sort((a, b) => a.sortOrder - b.sortOrder)
      return { ...app, videos: { ...app.videos, [channelId]: merged } }
    }
    case 'videoRemoved': {
      const { videoId } = event.payload
      const videos: Record<string, Video[]> = {}
      for (const cid of Object.keys(app.videos)) {
        videos[cid] = app.videos[cid].filter(v => v.id !== videoId)
      }
      return { ...app, videos }
    }
    case 'settingsUpdated': {
      return { ...app, settings: { ...app.settings, ...event.payload.settings } }
    }
    case 'appModeChanged': {
      return {
        ...app,
        appMode: event.payload.appMode,
      }
    }
    // ── Profile events ────────────────────────────────────────────────────
    case 'profileUpserted': {
      const { profile } = event.payload
      const idx = app.profiles.findIndex(p => p.id === profile.id)
      const profiles = idx === -1
        ? [...app.profiles, profile].sort((a, b) => a.sortOrder - b.sortOrder)
        : app.profiles.map((p, i) => (i === idx ? profile : p))
      const profileChannels = app.profileChannels[profile.id]
        ? app.profileChannels
        : { ...app.profileChannels, [profile.id]: [] }
      return { ...app, profiles, profileChannels }
    }
    case 'profileRemoved': {
      const { profileId } = event.payload
      const profiles = app.profiles.filter(p => p.id !== profileId)
      const profileChannels = { ...app.profileChannels }
      delete profileChannels[profileId]
      const activeProfileId =
        app.activeProfileId === profileId ? undefined : app.activeProfileId
      return { ...app, profiles, profileChannels, activeProfileId }
    }
    case 'profileChannelsUpdated': {
      const { profileId, channelIds } = event.payload
      return {
        ...app,
        profileChannels: { ...app.profileChannels, [profileId]: channelIds },
      }
    }
    case 'activeProfileChanged': {
      return {
        ...app,
        activeProfileId: event.payload.activeProfileId ?? undefined,
      }
    }
    case 'isEditingChanged': {
      return { ...app, isEditing: event.payload.isEditing }
    }
    case 'channelHiddenChanged': {
      const { profileId, channelId, hidden } = event.payload
      const current = new Set(app.profileHiddenChannels[profileId] ?? [])
      if (hidden) current.add(channelId)
      else current.delete(channelId)
      return {
        ...app,
        profileHiddenChannels: {
          ...app.profileHiddenChannels,
          [profileId]: Array.from(current),
        },
      }
    }
    // ── Playlist events ───────────────────────────────────────────────────
    case 'playlistUpserted': {
      const { playlist } = event.payload
      const idx = app.playlists.findIndex(p => p.id === playlist.id)
      const playlists = idx === -1
        ? [...app.playlists, playlist]
        : app.playlists.map((p, i) => (i === idx ? playlist : p))
      const playlistVideos = app.playlistVideos[playlist.id]
        ? app.playlistVideos
        : { ...app.playlistVideos, [playlist.id]: [] }
      return { ...app, playlists, playlistVideos }
    }
    case 'playlistRemoved': {
      const { playlistId } = event.payload
      const playlists = app.playlists.filter(p => p.id !== playlistId)
      const playlistVideos = { ...app.playlistVideos }
      delete playlistVideos[playlistId]
      return { ...app, playlists, playlistVideos }
    }
    case 'playlistVideosUpdated': {
      const { playlistId, videoIds } = event.payload
      return {
        ...app,
        playlistVideos: { ...app.playlistVideos, [playlistId]: videoIds },
      }
    }
    case 'activePlaylistChanged': {
      const { profileId, activePlaylistId } = event.payload
      return {
        ...app,
        profiles: app.profiles.map(p =>
          p.id === profileId
            ? { ...p, activePlaylistId: activePlaylistId ?? undefined }
            : p
        ),
      }
    }
    case 'favoriteChanged': {
      const { profileId, videoId, isFavorite } = event.payload
      const current = new Set(app.profileFavorites[profileId] ?? [])
      if (isFavorite) current.add(videoId)
      else current.delete(videoId)
      return {
        ...app,
        profileFavorites: {
          ...app.profileFavorites,
          [profileId]: Array.from(current),
        },
      }
    }
    // folderSelected and pinValidated are handled via callbacks, not state
    default:
      return app
  }
}

function reducer(state: FullState, action: Action): FullState {
  switch (action.kind) {
    case 'bridgeEvent':
      return { ...state, app: applyBridgeEvent(state.app, action.event) }
    case 'navigate':
      return { ...state, nav: action.nav }
    case 'setOnFolderSelected':
      return { ...state, onFolderSelected: action.fn }
    case 'setOnPINValidated':
      return { ...state, onPINValidated: action.fn }
    default:
      return state
  }
}

// ─── Context ───────────────────────────────────────────────────────────────
const AppStoreContext = createContext<AppStore | null>(null)

// ─── Provider ──────────────────────────────────────────────────────────────
export function AppStoreProvider({ children }: { children: React.ReactNode }) {
  const [fullState, reducerDispatch] = useReducer(reducer, {
    app: defaultState,
    nav: { screen: 'library' },
  })

  // Keep callbacks in a ref so we can call them without triggering re-renders
  const callbacksRef = useRef({
    onFolderSelected: fullState.onFolderSelected,
    onPINValidated: fullState.onPINValidated,
  })
  callbacksRef.current = {
    onFolderSelected: fullState.onFolderSelected,
    onPINValidated: fullState.onPINValidated,
  }

  // rAF-batched download progress: accumulate per-video progress values and
  // flush them all in one dispatch on the next animation frame. This coalesces
  // 6-12 individual downloadProgress events/sec into ≤1 state update per frame,
  // dramatically reducing React re-renders during active downloads.
  const progressBufferRef = useRef<Record<string, number>>({})
  const progressRafRef = useRef<number | null>(null)

  // Set up the bridge on mount
  useEffect(() => {
    initBridge((event: BridgeEvent) => {
      // Dispatch side-effect callbacks for transient events
      if (event.type === 'folderSelected') {
        callbacksRef.current.onFolderSelected?.(event.payload.path)
      } else if (event.type === 'pinValidated') {
        callbacksRef.current.onPINValidated?.(event.payload.valid)
      } else if (event.type === 'navigateTo') {
        reducerDispatch({ kind: 'navigate', nav: event.payload })
        return
      }

      // Batch download progress events — coalesce into one dispatch per frame
      if (event.type === 'downloadProgress') {
        const { videoId, progress } = event.payload
        progressBufferRef.current[videoId] = progress
        if (progressRafRef.current === null) {
          progressRafRef.current = requestAnimationFrame(() => {
            progressRafRef.current = null
            const batch = progressBufferRef.current
            progressBufferRef.current = {}
            reducerDispatch({
              kind: 'bridgeEvent',
              event: { type: 'downloadProgressBatch', payload: batch },
            })
          })
        }
        return
      }

      reducerDispatch({ kind: 'bridgeEvent', event })
    })

    // Request initial state from Swift
    sendBridge({ type: 'getState' })
  }, [])

  const dispatch = useCallback((event: BridgeEvent) => {
    reducerDispatch({ kind: 'bridgeEvent', event })
  }, [])

  const send = useCallback((msg: BridgeMessage) => {
    sendBridge(msg)
  }, [])

  const navigateTo = useCallback((nav: NavState) => {
    reducerDispatch({ kind: 'navigate', nav })
  }, [])

  const setOnFolderSelected = useCallback(
    (fn: ((path: string) => void) | undefined) => {
      reducerDispatch({ kind: 'setOnFolderSelected', fn })
    },
    []
  )

  const setOnPINValidated = useCallback(
    (fn: ((valid: boolean) => void) | undefined) => {
      reducerDispatch({ kind: 'setOnPINValidated', fn })
    },
    []
  )

  const store: AppStore = {
    state: fullState.app,
    nav: fullState.nav,
    navigateTo,
    dispatch,
    send,
    onFolderSelected: fullState.onFolderSelected,
    setOnFolderSelected,
    onPINValidated: fullState.onPINValidated,
    setOnPINValidated,
  }

  return React.createElement(AppStoreContext.Provider, { value: store }, children)
}

// ─── Hook ──────────────────────────────────────────────────────────────────
export function useAppStore(): AppStore {
  const ctx = useContext(AppStoreContext)
  if (!ctx) throw new Error('useAppStore must be used within AppStoreProvider')
  return ctx
}
