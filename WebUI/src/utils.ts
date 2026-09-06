import type { Video } from './types'

/**
 * Returns the thumbnail URL for a video.
 *
 * Swift already converts the on-disk path into a `localtube-thumb://`
 * URL (percent-encoded, with a `?v=N` cache-buster appended whenever the
 * file is replaced — e.g. after a Sync swaps an ffmpeg frame for the real
 * YouTube thumbnail). This helper just guards against an empty path and
 * against appending a second `?v=` when one is already present.
 */
export function thumbUrl(video: Pick<Video, 'thumbnailPath' | 'thumbnailVersion'>): string | undefined {
  if (!video.thumbnailPath) return undefined
  if (video.thumbnailPath.includes('?v=')) return video.thumbnailPath
  return `${video.thumbnailPath}?v=${video.thumbnailVersion ?? 0}`
}

/** "1.2 GB" style formatting for byte counts. */
export function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  let n = bytes
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${units[i]}`
}
