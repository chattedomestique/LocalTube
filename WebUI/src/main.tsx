import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import PlayerScreen from './screens/PlayerScreen.tsx'

// Swift injects window.__playerMode = true before the page loads when this
// WebView is used as the player controls overlay.  The main app window never
// sets this flag so the regular <App> renders there as normal.
const isPlayerMode = !!(window as unknown as Record<string, unknown>).__playerMode

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {isPlayerMode ? <PlayerScreen /> : <App />}
  </StrictMode>,
)
