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

// ─── Navigation ────────────────────────────────────────────────────────────
export type NavScreen = 'library' | 'channel' | 'settings' | 'editor'

export interface NavState {
  screen: NavScreen
  channelId?: string
}
