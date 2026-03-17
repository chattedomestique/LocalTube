import type { BridgeEvent, BridgeMessage } from './types'

// ─── Send a message to the Swift bridge ────────────────────────────────────
export function sendBridge(msg: BridgeMessage): void {
  const win = window as unknown as {
    webkit?: {
      messageHandlers?: {
        LocalTubeBridge?: {
          postMessage: (msg: BridgeMessage) => void
        }
      }
    }
  }
  win.webkit?.messageHandlers?.LocalTubeBridge?.postMessage(msg)
}

// ─── Initialize the JS-side bridge receiver ────────────────────────────────
// Swift calls window.LocalTubeBridge.dispatch(event, payload)
export function initBridge(onEvent: (e: BridgeEvent) => void): void {
  ;(window as unknown as Record<string, unknown>).LocalTubeBridge = {
    dispatch: (event: BridgeEvent) => {
      onEvent(event)
    },
  }
}
