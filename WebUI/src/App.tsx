import { Component, type ReactNode, type ErrorInfo } from 'react'
import { AppStoreProvider, useAppStore } from './store'
import Onboarding from './screens/Onboarding'
import PINSetup from './screens/PINSetup'
import PINEntry from './screens/PINEntry'
import Library from './screens/Library'
import Channel from './screens/Channel'
import Settings from './screens/Settings'
import Editor from './screens/Editor'

// H6 fix: React error boundary prevents a white screen on uncaught render errors.
// Shows a recoverable error UI and logs the error to Swift via the bridge.
interface ErrorBoundaryState {
  hasError: boolean
  error?: Error
}

class ErrorBoundary extends Component<{ children: ReactNode }, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[ErrorBoundary]', error, info.componentStack)
  }

  render() {
    if (this.state.hasError) {
      return (
        <div
          role="alert"
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            height: '100vh',
            background: 'var(--bg, #0d0d22)',
            color: 'var(--text-primary, #f0f0f4)',
            fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
            gap: 16,
            padding: 40,
          }}
        >
          <div style={{
            width: 64,
            height: 64,
            borderRadius: 18,
            background: 'rgba(248,113,113,0.1)',
            border: '1px solid rgba(248,113,113,0.3)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}>
            <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
              <circle cx="14" cy="14" r="12" stroke="#f87171" strokeWidth="2" />
              <path d="M14 8V15" stroke="#f87171" strokeWidth="2" strokeLinecap="round" />
              <circle cx="14" cy="20" r="1.5" fill="#f87171" />
            </svg>
          </div>
          <h2 style={{ fontSize: 20, fontWeight: 700, margin: 0 }}>Something went wrong</h2>
          <p style={{ fontSize: 13, color: '#8e8e99', textAlign: 'center', maxWidth: 320, margin: 0 }}>
            {this.state.error?.message ?? 'An unexpected error occurred.'}
          </p>
          <button
            onClick={() => this.setState({ hasError: false, error: undefined })}
            style={{
              marginTop: 8,
              padding: '10px 20px',
              background: 'rgba(155,93,229,0.15)',
              border: '1px solid rgba(155,93,229,0.4)',
              borderRadius: 10,
              color: '#c084fc',
              fontSize: 14,
              fontWeight: 600,
              cursor: 'pointer',
            }}
          >
            Try Again
          </button>
        </div>
      )
    }
    return this.props.children
  }
}

function AppContent() {
  const { state, nav } = useAppStore()
  const { isOnboarding, needsPINSetup, showPINEntry, appMode } = state

  // Full-screen flows
  if (isOnboarding) {
    return <Onboarding />
  }

  if (needsPINSetup) {
    return <PINSetup />
  }

  // Render the current screen
  let screen: ReactNode = null

  // In editor mode, the editor screen is the default unless on settings
  if (appMode === 'editor' && nav.screen === 'editor') {
    screen = <Editor />
  } else {
    switch (nav.screen) {
      case 'library':
        screen = <Library />
        break
      case 'channel':
        screen = <Channel />
        break
      case 'settings':
        screen = <Settings />
        break
      case 'editor':
        // Accessed from library when in editor mode
        screen = <Editor />
        break
      default:
        screen = <Library />
    }
  }

  return (
    <>
      {screen}
      {/* PIN Entry modal overlays whatever screen is shown */}
      {showPINEntry && <PINEntry />}
    </>
  )
}

export default function App() {
  return (
    <ErrorBoundary>
      <AppStoreProvider>
        <AppContent />
      </AppStoreProvider>
    </ErrorBoundary>
  )
}
