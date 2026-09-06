import { Component, useEffect, type ReactNode, type ErrorInfo } from 'react'
import { AppStoreProvider, useAppStore } from './store'
import { useThumbnailPreloader } from './lib/useThumbnailPreloader'
import Onboarding from './screens/Onboarding'
import PINSetup from './screens/PINSetup'
import PINEntry from './screens/PINEntry'
import Library from './screens/Library'
import Channel from './screens/Channel'
import Settings from './screens/Settings'
import Editor from './screens/Editor'
import Profiles from './screens/Profiles'
import ProfilePicker from './screens/ProfilePicker'
import LibraryUnavailable from './screens/LibraryUnavailable'
import EditorShell from './components/EditorShell'
import MountWithExit from './components/MountWithExit'
import QueueTray from './components/QueueTray'
import RelocateLibraryModal from './components/RelocateLibraryModal'
import ToastHost from './components/ToastHost'

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

// Tabs that live INSIDE the unified Editor shell. nav.screen values
// matching these are routed through EditorShell with the matching tab
// active.
const EDITOR_TAB_SCREENS = new Set(['editor', 'profiles', 'settings'])

/** The SQLite database couldn't be opened — nothing the app does would be
    saved, so say so loudly instead of showing an empty library. */
function LibraryLoadError({ message }: { message: string }) {
  return (
    <div role="alert" style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      gap: 14,
      padding: 40,
      textAlign: 'center',
      background: 'var(--bg)',
    }}>
      <h1 style={{ fontSize: 30, fontWeight: 800 }}>Library database could not be opened</h1>
      <p style={{ fontSize: 16, color: 'var(--text-secondary)', maxWidth: 560, lineHeight: 1.5 }}>
        LocalTube can't read its library database, so changes would not be saved.
        Quit and relaunch; if this keeps happening, restore a snapshot from
        <code style={{ fontFamily: 'ui-monospace, monospace' }}> ~/Library/Application Support/LocalTube/backups</code>.
      </p>
      <code style={{ fontSize: 13, color: '#fca5a5', fontFamily: 'ui-monospace, monospace', maxWidth: 640 }}>{message}</code>
    </div>
  )
}

function AppContent() {
  const { state, nav, navigateTo, libraryUI } = useAppStore()
  const {
    isOnboarding, needsPINSetup, showPINEntry, appMode, profiles, activeProfileId,
    libraryFolderAvailable, libraryLoadError,
  } = state

  // Eagerly decode every thumbnail in the catalog at the app root, once
  // per video. By the time any card mounts its image is already cached +
  // decoded — kills the scroll-time pop-in.
  useThumbnailPreloader(state.videos)

  // ── Mode-driven auto-navigation ────────────────────────────────────────
  // Entering editor mode always lands you on the Editor shell (Channels
  // tab by default). Exiting always returns you to the library (or the
  // picker if profiles exist and none is selected — handled below).
  // This eliminates the previous mess where Library kept showing in
  // editor mode and you had to know about a separate "Manage" button.
  useEffect(() => {
    if (appMode === 'editor' && !EDITOR_TAB_SCREENS.has(nav.screen)) {
      navigateTo({ screen: 'editor' })
    } else if (appMode === 'viewer' && EDITOR_TAB_SCREENS.has(nav.screen)) {
      navigateTo({ screen: 'library' })
    }
  }, [appMode, nav.screen, navigateTo])

  // Full-screen flows
  if (libraryLoadError) {
    return <LibraryLoadError message={libraryLoadError} />
  }

  if (isOnboarding) {
    return <Onboarding />
  }

  if (needsPINSetup) {
    return <PINSetup />
  }

  // Configured folder is unreachable (drive unplugged). Block everything
  // — playback, downloads, edits — until it's back or relocated.
  if (!libraryFolderAvailable) {
    return (
      <>
        <LibraryUnavailable />
        {libraryUI.pendingFolderAnalysis && <RelocateLibraryModal />}
        <ToastHost />
      </>
    )
  }

  // Render the current screen.
  // In editor mode, the three editor tabs (Channels/Profiles/Settings)
  // all render through the unified EditorShell so they share one top bar
  // with tabs + Exit. In viewer mode, we just render the raw screen.
  let screen: ReactNode
  if (appMode === 'editor' && EDITOR_TAB_SCREENS.has(nav.screen)) {
    const tabContent =
      nav.screen === 'profiles' ? <Profiles />
      : nav.screen === 'settings' ? <Settings />
      : <Editor />
    screen = (
      <EditorShell activeTab={nav.screen as 'editor' | 'profiles' | 'settings'}>
        {tabContent}
      </EditorShell>
    )
  } else {
    switch (nav.screen) {
      case 'channel':  screen = <Channel />;  break
      case 'settings': screen = <Settings />; break  // viewer-mode fallback
      case 'editor':   screen = <Library />;  break  // safety: viewer w/ stale nav
      case 'profiles': screen = <Library />;  break  // safety: viewer w/ stale nav
      case 'library':
      default:
        screen = <Library />
    }
  }

  // Profile picker is shown in viewer mode when at least one profile
  // exists and none is selected. Editor mode bypasses the picker.
  const showProfilePicker =
    appMode !== 'editor' && profiles.length > 0 && !activeProfileId

  // Queue tray is available in viewer mode with an active profile —
  // read-only for kids, editable for adults in the edit layer. Hidden
  // on the picker (no profile) and in admin mode.
  const showQueueTray = appMode !== 'editor' && !!activeProfileId && !showProfilePicker

  return (
    <>
      {screen}
      {showQueueTray && <QueueTray />}
      {/* Overlays wrapped in MountWithExit so they fade out smoothly
          instead of popping when their condition flips false. */}
      <MountWithExit show={showProfilePicker}>
        <ProfilePicker />
      </MountWithExit>
      <MountWithExit show={showPINEntry}>
        <PINEntry />
      </MountWithExit>
      {libraryUI.pendingFolderAnalysis && <RelocateLibraryModal />}
      <ToastHost />
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
