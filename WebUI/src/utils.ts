import type { Video } from './types'

/**
 * Returns the thumbnail URL for a video.
 *
 * Uses the raw filesystem path directly — WKWebView's
 * `allowFileAccessFromFileURLs` setting lets <img src="/abs/path">
 * resolve instantly from disk with no custom-scheme round-trip.
 *
 * A ?v=N query-string is appended for cache-busting when
 * thumbnailVersion changes (e.g. after a Sync refresh replaces
 * an ffmpeg frame with a real YouTube thumbnail).
 */
export function thumbUrl(video: Pick<Video, 'thumbnailPath' | 'thumbnailVersion'>): string | undefined {
  if (!video.thumbnailPath) return undefined
  return `${video.thumbnailPath}?v=${video.thumbnailVersion ?? 0}`
}
