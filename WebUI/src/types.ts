// ─── Download State ────────────────────────────────────────────────────────
export type DownloadState = 'queued' | 'downloading' | 'ready' | 'error'

// ─── Channel Type ──────────────────────────────────────────────────────────
export type ChannelType = 'source' | 'custom'

// ─── Core Models ───────────────────────────────────────────────────────────
export interface Video {
  id: string
  channelId: string
  youtubeVideoId: string
  title: string
  localFilePath: string
  thumbnailPath: string
  thumbnailVersion: number
  downloadedAt: string
  durationSeconds: number
  resumePositionSeconds: number
  downloadState: DownloadState
  downloadProgress: number
  downloadError?: string
  sortOrder: number
}

export interface Channel {
  id: string
  displayName: string
  emoji?: string
  type: ChannelType
  youtubeChannelId?: string
  folderName: string
  sortOrder: number
  createdAt: string
  bannerPath?: string
  /** ISO timestamp of last successful sync. Undefined = never synced. */
  lastSyncedAt?: string
  /** Last sync's error message, if it failed. Cleared on next success. */
  lastSyncError?: string
}

export interface AppSettings {
  downloadFolderPath?: string
  editorAutoLockMinutes: number
  downloadQuality: string
}

export interface Profile {
  id: string
  name: string
  emoji?: string
  /** Phosphor icon name (e.g. "Heart") — see lib/profileIcons.ts */
  icon?: string
  /** Color key from lib/profileColors.ts (e.g. "coral") */
  color?: string
  sortOrder: number
  createdAt: string
  /** The playlist the tray shows / plays through. */
  activePlaylistId?: string
  /** Channel-playback end behaviour (Phase 4): repeat/sequential/random/exit */
  autoPlaybackMode?: string
}

export interface Playlist {
  id: string
  profileId: string
  name: string
  sortOrder: number
  isSystem: boolean
  createdAt: string
}

// ─── App Mode ──────────────────────────────────────────────────────────────
export type AppMode = 'viewer' | 'editor'

// ─── App State ─────────────────────────────────────────────────────────────
export interface AppState {
  channels: Channel[]
  videos: Record<string, Video[]>
  appMode: AppMode
  isOnboarding: boolean
  needsPINSetup: boolean
  showPINEntry: boolean
  settings: AppSettings
  dependencyStatus: {
    ytDlp: boolean
    ffmpeg: boolean
  }
  activeDownload?: {
    videoId: string
    progress: number
    title: string
  }
  // editorRemainingSeconds removed with the auto-lock timer in the
  // editing-model redesign. Kept on the wire payload as a constant 0
  // for transitional safety; not exposed in the React state shape.
  syncingChannelIds: string[]
  /** Inline edit layer flag (separate from Admin mode). When true,
      the active profile's pages show edit affordances and block
      navigation into deeper layers. */
  isEditing: boolean
  profiles: Profile[]
  /** profileId → list of channel ids assigned to that profile */
  profileChannels: Record<string, string[]>
  /** profileId → list of favorited video ids. Per-profile per-video. */
  profileFavorites: Record<string, string[]>
  /** profileId → list of channel ids hidden from this profile (assignment
      stays in profileChannels; just filtered out of the viewer-mode UI). */
  profileHiddenChannels: Record<string, string[]>
  /** All playlists across all profiles. */
  playlists: Playlist[]
  /** playlistId → ordered video ids. */
  playlistVideos: Record<string, string[]>
  activeProfileId?: string
}

// ─── Bridge Events (Swift → JS) ────────────────────────────────────────────
export type BridgeEvent =
  | { type: 'stateUpdate';       payload: Partial<AppState> }
  | { type: 'downloadProgress';  payload: { videoId: string; progress: number } }
  | { type: 'downloadProgressBatch'; payload: Record<string, number> }
  | { type: 'downloadCompleted'; payload: { videoId: string } }
  | { type: 'downloadError';     payload: { videoId: string; error: string } }
  | { type: 'folderSelected';    payload: { path: string } }
  | { type: 'pinValidated';      payload: { valid: boolean } }
  // editorTimerTick removed with the auto-lock timer.
  | { type: 'navigateTo';        payload: NavState }
  // Targeted diff events — emitted instead of full stateUpdate when only
  // a single slice changed. The React reducer applies them as O(1) patches.
  | { type: 'channelUpserted';   payload: { channel: Channel } }
  | { type: 'channelRemoved';    payload: { channelId: string } }
  | { type: 'videosUpserted';    payload: { channelId: string; videos: Video[] } }
  | { type: 'videoRemoved';      payload: { videoId: string } }
  | { type: 'settingsUpdated';   payload: { settings: AppSettings } }
  | { type: 'appModeChanged';    payload: { appMode: AppMode } }
  // Profile diff events
  | { type: 'profileUpserted';   payload: { profile: Profile } }
  | { type: 'profileRemoved';    payload: { profileId: string } }
  | { type: 'profileChannelsUpdated'; payload: { profileId: string; channelIds: string[] } }
  | { type: 'activeProfileChanged';   payload: { activeProfileId: string | null } }
  | { type: 'favoriteChanged';        payload: { profileId: string; videoId: string; isFavorite: boolean } }
  | { type: 'isEditingChanged';       payload: { isEditing: boolean } }
  | { type: 'channelHiddenChanged';   payload: { profileId: string; channelId: string; hidden: boolean } }
  | { type: 'playlistUpserted';       payload: { playlist: Playlist } }
  | { type: 'playlistRemoved';        payload: { playlistId: string } }
  | { type: 'playlistVideosUpdated';  payload: { playlistId: string; videoIds: string[] } }
  | { type: 'activePlaylistChanged';  payload: { profileId: string; activePlaylistId: string | null } }

// ─── Bridge Messages (JS → Swift) ─────────────────────────────────────────
export type BridgeMessage =
  | { type: 'getState' }
  | { type: 'playVideo';        payload: { videoId: string } }
  | { type: 'stopPlayer' }
  | { type: 'openFolderPicker' }
  | { type: 'validatePIN';      payload: { pin: string } }
  | { type: 'setPIN';           payload: { pin: string } }
  | { type: 'requestEditorMode' }
  | { type: 'exitEditorMode' }
  | { type: 'addChannel';       payload: { displayName: string; emoji?: string; type: ChannelType; youtubeChannelId?: string } }
  | { type: 'deleteChannel';    payload: { channelId: string } }
  | { type: 'updateChannel';    payload: Channel }
  | { type: 'addVideoURLs';     payload: { channelId: string; urls: string[] } }
  | { type: 'deleteVideo';      payload: { videoId: string } }
  | { type: 'retryDownload';    payload: { videoId: string } }
  | { type: 'saveSettings';     payload: AppSettings }
  | { type: 'checkDependencies' }
  | { type: 'syncChannel';         payload: { channelId: string } }
  | { type: 'uploadChannelBanner'; payload: { channelId: string } }
  | { type: 'setActiveProfile';    payload: { profileId: string | null } }
  | { type: 'addProfile';          payload: { name: string; emoji?: string; icon?: string; color?: string; channelIds?: string[] } }
  | { type: 'updateProfile';       payload: { id: string; name?: string; emoji?: string; icon?: string; color?: string } }
  | { type: 'deleteProfile';       payload: { profileId: string } }
  | { type: 'setProfileChannels';  payload: { profileId: string; channelIds: string[] } }
  | { type: 'dismissPINEntry' }
  | { type: 'toggleFavorite';      payload: { profileId: string; videoId: string; isFavorite: boolean } }
  | { type: 'requestEditMode' }
  | { type: 'endEditMode' }
  | { type: 'toggleChannelHidden'; payload: { profileId: string; channelId: string; hidden: boolean } }
  | { type: 'createPlaylist';      payload: { profileId: string; name: string } }
  | { type: 'renamePlaylist';      payload: { playlistId: string; name: string } }
  | { type: 'deletePlaylist';      payload: { playlistId: string } }
  | { type: 'setActivePlaylist';   payload: { profileId: string; playlistId: string | null } }
  | { type: 'addToPlaylist';       payload: { playlistId: string; videoId: string } }
  | { type: 'removeFromPlaylist';  payload: { playlistId: string; videoId: string } }
  | { type: 'reorderPlaylist';     payload: { playlistId: string; videoIds: string[] } }
  | { type: 'clearPlaylist';       payload: { playlistId: string } }

// ─── Navigation ────────────────────────────────────────────────────────────
export type NavScreen = 'library' | 'channel' | 'settings' | 'editor' | 'profiles'

export interface NavState {
  screen: NavScreen
  channelId?: string
}
