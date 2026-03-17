import type { ReactNode } from 'react'
import { AppStoreProvider, useAppStore } from './store'
import Onboarding from './screens/Onboarding'
import PINSetup from './screens/PINSetup'
import PINEntry from './screens/PINEntry'
import Library from './screens/Library'
import Channel from './screens/Channel'
import Settings from './screens/Settings'
import Editor from './screens/Editor'

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
    <AppStoreProvider>
      <AppContent />
    </AppStoreProvider>
  )
}
