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
  sortOrder: number
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
  editorRemainingSeconds: number
  syncingChannelIds: string[]
  profiles: Profile[]
  /** profileId → list of channel ids assigned to that profile */
  profileChannels: Record<string, string[]>
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
  | { type: 'editorTimerTick';   payload: { remainingSeconds: number } }
  | { type: 'navigateTo';        payload: NavState }
  // Targeted diff events — emitted instead of full stateUpdate when only
  // a single slice changed. The React reducer applies them as O(1) patches.
  | { type: 'channelUpserted';   payload: { channel: Channel } }
  | { type: 'channelRemoved';    payload: { channelId: string } }
  | { type: 'videosUpserted';    payload: { channelId: string; videos: Video[] } }
  | { type: 'videoRemoved';      payload: { videoId: string } }
  | { type: 'settingsUpdated';   payload: { settings: AppSettings } }
  | { type: 'appModeChanged';    payload: { appMode: AppMode; editorRemainingSeconds: number } }
  // Profile diff events
  | { type: 'profileUpserted';   payload: { profile: Profile } }
  | { type: 'profileRemoved';    payload: { profileId: string } }
  | { type: 'profileChannelsUpdated'; payload: { profileId: string; channelIds: string[] } }
  | { type: 'activeProfileChanged';   payload: { activeProfileId: string | null } }

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
  | { type: 'addProfile';          payload: { name: string; emoji?: string; channelIds?: string[] } }
  | { type: 'updateProfile';       payload: { id: string; name?: string; emoji?: string } }
  | { type: 'deleteProfile';       payload: { profileId: string } }
  | { type: 'setProfileChannels';  payload: { profileId: string; channelIds: string[] } }

// ─── Navigation ────────────────────────────────────────────────────────────
export type NavScreen = 'library' | 'channel' | 'settings' | 'editor' | 'profiles'

export interface NavState {
  screen: NavScreen
  channelId?: string
}
