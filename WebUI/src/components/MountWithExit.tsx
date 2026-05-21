import { useState, useEffect, type ReactNode } from 'react'

/**
 * Wrap a conditionally-mounted overlay to give it BOTH an enter and an
 * exit animation. React unmounts the moment the condition flips false,
 * which prevents any CSS transition from running on the way out — that's
 * what "popping" looks like.
 *
 * This keeps the children mounted through a four-phase state machine
 *   hidden → entering → visible → exiting → hidden
 * The wrapper's opacity is driven from the phase; the actual fade
 * happens via a CSS transition between the entering→visible and the
 * visible→exiting transitions. After exiting, a setTimeout flips back
 * to hidden and the children finally unmount.
 *
 * Children manage their own positioning (the picker uses position:fixed,
 * modals use the .modal-backdrop class). The wrapper does NOT add any
 * positioning of its own — opacity on a block element propagates to all
 * descendants regardless of their own position scheme.
 */
export default function MountWithExit({
  show,
  children,
  fadeMs = 220,
}: {
  show: boolean
  children: ReactNode
  fadeMs?: number
}) {
  type Phase = 'hidden' | 'entering' | 'visible' | 'exiting'
  const [phase, setPhase] = useState<Phase>(show ? 'visible' : 'hidden')

  useEffect(() => {
    if (show) {
      if (phase === 'hidden') {
        setPhase('entering')
      } else if (phase === 'entering') {
        // Wait one frame for opacity:0 to paint, then flip to visible
        // so the CSS opacity transition has somewhere to interpolate to.
        const id = requestAnimationFrame(() => setPhase('visible'))
        return () => cancelAnimationFrame(id)
      } else if (phase === 'exiting') {
        // Cancel an in-flight exit and ride back to visible.
        setPhase('visible')
      }
    } else {
      if (phase === 'visible' || phase === 'entering') {
        setPhase('exiting')
      } else if (phase === 'exiting') {
        const t = setTimeout(() => setPhase('hidden'), fadeMs)
        return () => clearTimeout(t)
      }
    }
  }, [show, phase, fadeMs])

  if (phase === 'hidden') return null

  const opacity = phase === 'visible' ? 1 : 0

  return (
    <div style={{
      opacity,
      transition: `opacity ${fadeMs}ms cubic-bezier(0.4, 0, 0.2, 1)`,
      // While invisible, pass clicks through so the wrapper never blocks
      // the underlying screen during the fade-out tail.
      pointerEvents: phase === 'visible' ? 'auto' : 'none',
    }}>
      {children}
    </div>
  )
}
