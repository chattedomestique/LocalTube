import { useEffect, useState } from 'react'
import { useAppStore } from '../store'
import type { LibraryRelocationMode } from '../types'
import { formatBytes } from '../utils'

/**
 * Shown after Swift answers `chooseLibraryFolder` with an analysis of the
 * folder the parent picked. Offers the three safe ways to change where
 * the library lives:
 *
 *   Move   — physically move every channel folder into the new place and
 *            re-point the database (the normal "I bought a bigger drive").
 *   Adopt  — the files are already there (moved in Finder); just re-point.
 *   Switch — leave existing videos where they are; only new downloads go
 *            to the new folder.
 *
 * Before this existed, "Change" simply rewrote the download path and every
 * previously downloaded video was orphaned at its old absolute path.
 */
export default function RelocateLibraryModal() {
  const { state, send, libraryUI, clearPendingFolderAnalysis } = useAppStore()
  const analysis = libraryUI.pendingFolderAnalysis
  const progress = libraryUI.relocationProgress
  const [chosenMode, setChosenMode] = useState<LibraryRelocationMode | null>(null)

  // A brand-new library (nothing downloaded yet) has nothing to move —
  // switch straight away without asking. Derived, not stored, so the
  // effect below only talks to Swift and never sets state.
  const autoSwitch = !!analysis
    && analysis.exists && analysis.libraryVideoCount === 0
    && !analysis.isCurrentRoot && analysis.writable
  const autoSwitchPath = autoSwitch ? analysis.path : null

  useEffect(() => {
    if (autoSwitchPath) {
      send({ type: 'relocateLibrary', payload: { path: autoSwitchPath, mode: 'switch' } })
    }
  }, [autoSwitchPath, send])

  if (!analysis) return null

  const run = (mode: LibraryRelocationMode) => {
    setChosenMode(mode)
    send({ type: 'relocateLibrary', payload: { path: analysis.path, mode } })
  }

  const busyMode: LibraryRelocationMode | null = chosenMode ?? (autoSwitch ? 'switch' : null)
  const busy = busyMode !== null || !!state.isRelocating
  const folderName = analysis.path.split('/').filter(Boolean).pop() ?? analysis.path
  const spaceOk = analysis.freeBytes === 0 || analysis.libraryBytes === 0 || analysis.freeBytes >= analysis.libraryBytes

  let blocker: string | null = null
  if (!analysis.exists) blocker = 'That folder no longer exists.'
  else if (analysis.isCurrentRoot) blocker = 'That is already the library folder.'
  else if (analysis.isInsideCurrentRoot) blocker = 'The new folder cannot be inside the current library folder.'
  else if (analysis.containsCurrentRoot) blocker = 'The new folder cannot contain the current library folder.'

  return (
    <div className="modal-backdrop" role="presentation" style={{ zIndex: 150 }}>
      <div
        className="modal-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="relocate-title"
        style={{ width: 560, padding: '36px 36px 28px' }}
      >
        <h2 id="relocate-title" style={{ fontSize: 24, marginBottom: 6 }}>
          {busy ? 'Updating library location…' : 'Change library folder'}
        </h2>
        <p style={{ fontSize: 15, color: 'var(--text-secondary)', marginBottom: 18, lineHeight: 1.5 }}>
          New folder: <span style={{ fontFamily: 'ui-monospace, monospace', color: 'var(--text-primary)' }}>{analysis.path}</span>
        </p>

        {busy ? (
          <div style={{ padding: '12px 0 4px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
              <svg className="spinner" width="18" height="18" viewBox="0 0 12 12" fill="none">
                <circle cx="6" cy="6" r="4.5" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
                <path d="M6 1.5A4.5 4.5 0 0 1 10.5 6" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              <span style={{ fontSize: 15, color: 'var(--text-secondary)' }}>
                {busyMode === 'move'
                  ? progress
                    ? `Moving ${progress.channel} (${progress.done} of ${progress.total})…`
                    : 'Preparing to move files…'
                  : busyMode === 'adopt'
                    ? 'Checking files in the new folder…'
                    : 'Switching download folder…'}
              </span>
            </div>
            {busyMode === 'move' && progress && progress.total > 0 && (
              <div style={{ height: 6, background: 'rgba(255,255,255,0.1)', borderRadius: 3, overflow: 'hidden' }}>
                <div style={{
                  height: '100%',
                  width: `${Math.round((progress.done / progress.total) * 100)}%`,
                  background: 'linear-gradient(90deg, var(--accent), var(--accent-hover))',
                  transition: 'width 300ms ease',
                }} />
              </div>
            )}
            <p style={{ fontSize: 13, color: 'var(--text-tertiary)', marginTop: 12 }}>
              Keep LocalTube open until this finishes. The database was backed up first.
            </p>
          </div>
        ) : blocker ? (
          <>
            <Notice kind="error">{blocker}</Notice>
            <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
              <button className="lt-btn-secondary" onClick={clearPendingFolderAnalysis}>Close</button>
            </div>
          </>
        ) : (
          <>
            <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginBottom: 16, display: 'flex', gap: 18, flexWrap: 'wrap' }}>
              <span>{analysis.libraryReadyCount} downloaded video{analysis.libraryReadyCount === 1 ? '' : 's'} ({formatBytes(analysis.libraryBytes)})</span>
              {analysis.freeBytes > 0 && <span>{formatBytes(analysis.freeBytes)} free in {folderName}</span>}
              {analysis.matchingChannelFolders > 0 && (
                <span style={{ color: 'var(--success)' }}>
                  {analysis.matchingChannelFolders} of {analysis.totalChannels} channel folder{analysis.totalChannels === 1 ? '' : 's'} already here
                </span>
              )}
            </div>

            {!analysis.writable && <Notice kind="warning">LocalTube can't write to this folder. You can still adopt files that are already there.</Notice>}
            {analysis.writable && !spaceOk && <Notice kind="warning">Not enough free space to move the whole library here.</Notice>}

            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <OptionButton
                title="Move library here"
                description="Move every channel folder into the new folder and update the library. Recommended when switching to a bigger drive."
                disabled={!analysis.canMove || !spaceOk}
                primary
                onClick={() => run('move')}
              />
              <OptionButton
                title="Use files already in this folder"
                description={analysis.matchingChannelFolders > 0
                  ? 'The channel folders were moved here in Finder. Re-point the library at them without copying anything.'
                  : 'No channel folders from this library were found here yet.'}
                disabled={!analysis.canAdopt}
                onClick={() => run('adopt')}
              />
              <OptionButton
                title="Only save new downloads here"
                description="Leave existing videos where they are (they keep playing from the old folder) and put new downloads in the new folder."
                disabled={!analysis.writable}
                onClick={() => run('switch')}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
              <button className="lt-btn-ghost" onClick={clearPendingFolderAnalysis}>Cancel</button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function OptionButton({
  title, description, disabled, primary, onClick,
}: {
  title: string
  description: string
  disabled?: boolean
  primary?: boolean
  onClick: () => void
}) {
  const [hover, setHover] = useState(false)
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        textAlign: 'left',
        padding: '14px 16px',
        borderRadius: 12,
        border: `1px solid ${primary && !disabled ? 'rgba(155,93,229,0.45)' : 'rgba(255,255,255,0.12)'}`,
        background: disabled
          ? 'rgba(255,255,255,0.02)'
          : hover
            ? (primary ? 'rgba(155,93,229,0.22)' : 'rgba(255,255,255,0.08)')
            : (primary ? 'rgba(155,93,229,0.12)' : 'rgba(255,255,255,0.04)'),
        color: 'var(--text-primary)',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.45 : 1,
        transition: 'background 140ms ease, border-color 140ms ease',
      }}
    >
      <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 3, color: primary && !disabled ? 'var(--accent)' : 'var(--text-primary)' }}>{title}</div>
      <div style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.45 }}>{description}</div>
    </button>
  )
}

function Notice({ kind, children }: { kind: 'error' | 'warning'; children: React.ReactNode }) {
  const color = kind === 'error' ? '248,113,113' : '251,191,36'
  return (
    <div style={{
      padding: '10px 14px',
      borderRadius: 10,
      background: `rgba(${color},0.10)`,
      border: `1px solid rgba(${color},0.30)`,
      color: kind === 'error' ? '#fca5a5' : '#fde68a',
      fontSize: 13,
      marginBottom: 14,
      lineHeight: 1.45,
    }}>
      {children}
    </div>
  )
}
