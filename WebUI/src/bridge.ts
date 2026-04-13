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

// M12 fix: Send with a timeout that resolves when Swift responds with a
// matching event type. Falls back to fire-and-forget if no response arrives.
export function sendBridgeWithTimeout(
  msg: BridgeMessage,
  expectedEvent: string,
  timeoutMs = 10_000,
): Promise<BridgeEvent | null> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      console.warn(`Bridge: timeout waiting for '${expectedEvent}' after ${timeoutMs}ms`)
      resolve(null)
    }, timeoutMs)

    // Temporarily listen for the expected response event
    const originalDispatch = (window as unknown as Record<string, unknown>).LocalTubeBridge as {
      dispatch: (event: BridgeEvent) => void
      _originalDispatch?: (event: BridgeEvent) => void
    }
    const orig = originalDispatch.dispatch
    originalDispatch.dispatch = (event: BridgeEvent) => {
      if (event.type === expectedEvent) {
        clearTimeout(timer)
        originalDispatch.dispatch = orig
        resolve(event)
      }
      // Always forward the event to the original handler
      orig(event)
    }

    sendBridge(msg)
  })
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
