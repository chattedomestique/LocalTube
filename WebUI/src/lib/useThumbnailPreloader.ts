import { useEffect, useRef } from 'react'
import type { Video } from '../types'
import { thumbUrl } from '../utils'

/**
 * Eagerly preloads every video thumbnail in the catalog the first time
 * the library is hydrated (and again whenever a new video appears).
 *
 * Why: even though our thumbnails are local files served via the
 * localtube-thumb:// scheme handler, the <img> tag's decode is async.
 * 24 cards mounting in parallel each fire their own background decode;
 * some finish before others, so the user sees pixels appear in waves
 * as they scroll ("blinking"). Decoding everything off the card render
 * path means by the time any card mounts, its image is already in the
 * browser cache AND decoded — first paint shows the pixels.
 *
 * Implementation:
 *   - Track preloaded URLs in a ref so we never re-decode an image
 *     across renders. New videos (e.g. after a download completes) get
 *     preloaded incrementally.
 *   - Off-thread decode via Image.decode(). We ignore errors — onError
 *     on the real <img> tag handles display fallback.
 *   - No throttling: thumbnails are local files, browsers parallelise
 *     decodes across cores, and the cache lookup later is free.
 */
export function useThumbnailPreloader(videos: Record<string, Video[]>) {
  const preloaded = useRef<Set<string>>(new Set())

  useEffect(() => {
    for (const list of Object.values(videos)) {
      for (const v of list) {
        if (!v.thumbnailPath) continue
        const url = thumbUrl(v)
        if (!url || preloaded.current.has(url)) continue
        preloaded.current.add(url)
        const img = new Image()
        img.src = url
        img.decode().catch(() => { /* fall back to live <img> rendering */ })
      }
    }
  }, [videos])
}
