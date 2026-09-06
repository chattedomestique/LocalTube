import type { ReactNode } from 'react'
import { useState, useEffect, useMemo } from 'react'
import { useAppStore } from '../store'
import type { AppSettings, LibraryScanResult } from '../types'
import { formatBytes } from '../utils'

const QUALITY_OPTIONS = [
  { value: 'best',     label: 'Best Available (up to 1080p)' },
  { value: '1080p',    label: '1080p (Full HD)' },
  { value: '720p',     label: '720p (HD)' },
  { value: '480p',     label: '480p (SD)' },
  { value: '360p',     label: '360p (Low)' },
  { value: 'audio',    label: 'Audio Only' },
]

// M14 fix: Added htmlFor/id association for accessible labels.
function SettingRow({
  label,
  description,
  htmlFor,
  children,
}: {
  label: string
  description?: ReactNode
  htmlFor?: string
  children: ReactNode
}) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 24,
      padding: '16px 20px',
    }}>
      <div style={{ minWidth: 0 }}>
        <label
          htmlFor={htmlFor}
          style={{
            fontSize: 14,
            fontWeight: 500,
            color: 'var(--text-primary)',
            marginBottom: description ? 3 : 0,
            display: 'block',
          }}
        >
          {label}
        </label>
        {description && (
          <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
            {description}
          </div>
        )}
      </div>
      <div style={{ flexShrink: 0 }}>
        {children}
      </div>
    </div>
  )
}

function Divider() {
  return <div style={{ height: 1, background: 'rgba(255,255,255,0.09)', margin: '0 20px' }} />
}

const PANEL_STYLE = {
  background: 'linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.04) 100%)',
  backgroundColor: 'rgba(20,20,25,0.7)',
  backdropFilter: 'blur(20px) saturate(180%)',
  WebkitBackdropFilter: 'blur(20px) saturate(180%)',
  border: '0.5px solid rgba(255,255,255,0.12)',
  borderRadius: 14,
  overflow: 'hidden',
  boxShadow: '0 4px 16px rgba(0,0,0,0.35), 0 1px 4px rgba(0,0,0,0.2), inset 0 0 0 1px rgba(255,255,255,0.06)',
} as const

// Only these keys are user-editable here. The download folder is changed
// through the relocation flow (Change… button), never by "Save".
type EditableSettings = Pick<AppSettings, 'downloadQuality' | 'checkDepsOnLaunch' | 'editorAutoLockMinutes'>
function pickEditable(s: AppSettings): EditableSettings {
  return {
    downloadQuality: s.downloadQuality ?? 'best',
    checkDepsOnLaunch: s.checkDepsOnLaunch ?? true,
    editorAutoLockMinutes: s.editorAutoLockMinutes ?? 10,
  }
}

export default function Settings() {
  const { state, send } = useAppStore()
  const { settings, dependencyStatus, lastScan, isScanning, videos, appVersion } = state
  const [local, setLocal] = useState<EditableSettings>(() => pickEditable(settings))
  const [saved, setSaved] = useState(false)
  const [checkingDeps, setCheckingDeps] = useState(false)

  useEffect(() => {
    setLocal(pickEditable(settings))
  }, [settings])

  const handleSave = () => {
    send({ type: 'saveSettings', payload: { ...settings, ...local } })
    setSaved(true)
    setTimeout(() => setSaved(false), 2000)
  }

  const handleChangePath = () => {
    send({ type: 'chooseLibraryFolder' })
  }

  const handleCheckDeps = () => {
    setCheckingDeps(true)
    send({ type: 'checkDependencies' })
    setTimeout(() => setCheckingDeps(false), 3000)
  }

  const hasChanges = JSON.stringify(local) !== JSON.stringify(pickEditable(settings))

  const counts = useMemo(() => {
    let total = 0, ready = 0, failed = 0, pending = 0
    for (const list of Object.values(videos)) {
      for (const v of list) {
        total++
        if (v.downloadState === 'ready') ready++
        else if (v.downloadState === 'error') failed++
        else pending++
      }
    }
    return { total, ready, failed, pending }
  }, [videos])

  const folderPath = settings.downloadFolderPath ?? ''
  const folderName = folderPath.split('/').filter(Boolean).pop() ?? folderPath

  return (
    <div className="screen-enter" style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--bg)',
    }}>
      {/* Top bar provided by EditorShell — Settings just renders content. */}

      {/* Content */}
      <div style={{
        flex: 1,
        overflowY: 'auto',
        padding: '24px',
        display: 'flex',
        flexDirection: 'column',
        gap: 20,
        maxWidth: 640,
        width: '100%',
        margin: '0 auto',
      }}>
        {/* Library section */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>Library</p>
          <div style={PANEL_STYLE}>
            <SettingRow
              label="Library Folder"
              description={
                <span
                  title={folderPath}
                  style={{
                    fontFamily: 'ui-monospace, monospace',
                    display: 'block',
                    maxWidth: 360,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {folderPath || 'Not set'}
                </span>
              }
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                {folderPath && (
                  <button
                    className="lt-btn-ghost"
                    onClick={() => send({ type: 'revealLibraryFolder' })}
                    style={{ padding: '6px 10px', fontSize: 12 }}
                    title={`Reveal ${folderName} in Finder`}
                  >
                    Show in Finder
                  </button>
                )}
                <button
                  className="lt-btn-secondary"
                  onClick={handleChangePath}
                  style={{ padding: '6px 12px', fontSize: 12 }}
                  title="Move the library, adopt a folder you moved by hand, or just change where new downloads go"
                >
                  Change…
                </button>
              </div>
            </SettingRow>

            <Divider />

            <SettingRow
              label="Verify Library"
              description={
                <>
                  {counts.ready} of {counts.total} videos downloaded
                  {counts.pending > 0 && ` · ${counts.pending} pending`}
                  {counts.failed > 0 && ` · ${counts.failed} failed`}
                  <br />
                  Checks every video file is where the library expects it, repairs
                  paths after a move, and re-queues anything that's gone missing.
                </>
              }
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                {counts.failed > 0 && (
                  <button
                    className="lt-btn-secondary"
                    onClick={() => send({ type: 'retryFailedDownloads', payload: {} })}
                    style={{ padding: '6px 12px', fontSize: 12 }}
                  >
                    Retry {counts.failed} failed
                  </button>
                )}
                <button
                  className="lt-btn-secondary"
                  onClick={() => send({ type: 'verifyLibrary' })}
                  disabled={!!isScanning}
                  style={{ padding: '6px 12px', fontSize: 12 }}
                >
                  {isScanning ? (
                    <>
                      <svg className="spinner" width="13" height="13" viewBox="0 0 13 13" fill="none">
                        <circle cx="6.5" cy="6.5" r="5" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
                        <path d="M6.5 1.5A5 5 0 0 1 11.5 6.5" stroke="var(--text-secondary)" strokeWidth="1.5" strokeLinecap="round" />
                      </svg>
                      Scanning…
                    </>
                  ) : 'Verify Now'}
                </button>
              </div>
            </SettingRow>

            {lastScan && (
              <>
                <Divider />
                <ScanSummary scan={lastScan} />
              </>
            )}
          </div>
        </div>

        {/* Downloads section */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>Downloads</p>
          <div style={PANEL_STYLE}>
            <SettingRow
              label="Download Quality"
              description="Quality for new downloads. H.264 is preferred so videos play smoothly."
              htmlFor="setting-quality"
            >
              <select
                id="setting-quality"
                className="lt-input"
                value={local.downloadQuality}
                onChange={e => setLocal(prev => ({ ...prev, downloadQuality: e.target.value }))}
                style={{ width: 220, padding: '7px 32px 7px 12px' }}
              >
                {QUALITY_OPTIONS.map(opt => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </SettingRow>

            <Divider />

            <SettingRow
              label="Check tools on launch"
              description="Verify yt-dlp and ffmpeg are installed every time LocalTube starts"
              htmlFor="setting-checkdeps"
            >
              <input
                id="setting-checkdeps"
                type="checkbox"
                checked={local.checkDepsOnLaunch ?? true}
                onChange={e => setLocal(prev => ({ ...prev, checkDepsOnLaunch: e.target.checked }))}
                style={{ width: 18, height: 18, accentColor: 'var(--accent)' }}
              />
            </SettingRow>
          </div>
        </div>


        {/* Dependencies section */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>Dependencies</p>
          <div style={PANEL_STYLE}>
            <SettingRow
              label="yt-dlp"
              description="YouTube download engine"
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <DepStatus ok={dependencyStatus.ytDlp} />
              </div>
            </SettingRow>

            <Divider />

            <SettingRow
              label="ffmpeg"
              description="Audio/video processing"
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <DepStatus ok={dependencyStatus.ffmpeg} />
              </div>
            </SettingRow>

            <Divider />

            <div style={{ padding: '12px 20px' }}>
              <button
                className="lt-btn-secondary"
                onClick={handleCheckDeps}
                disabled={checkingDeps}
                style={{ fontSize: 13 }}
              >
                {checkingDeps ? (
                  <>
                    <svg className="spinner" width="13" height="13" viewBox="0 0 13 13" fill="none">
                      <circle cx="6.5" cy="6.5" r="5" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
                      <path d="M6.5 1.5A5 5 0 0 1 11.5 6.5" stroke="var(--text-secondary)" strokeWidth="1.5" strokeLinecap="round" />
                    </svg>
                    Checking...
                  </>
                ) : (
                  <>
                    <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                      <path d="M11 6.5A4.5 4.5 0 1 1 6.5 2M11 2v3H8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    Check Dependencies
                  </>
                )}
              </button>
            </div>
          </div>
        </div>

        {/* About */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>About</p>
          <div style={PANEL_STYLE}>
            <SettingRow label="LocalTube" description="Your offline YouTube library">
              <span style={{ fontSize: 12, color: 'var(--text-tertiary)', fontFamily: 'ui-monospace, monospace' }}>
                v{appVersion ?? '—'}
              </span>
            </SettingRow>
            <Divider />
            <SettingRow
              label="Software Update"
              description="LocalTube checks for new versions automatically once a day and installs them with your OK."
            >
              <button
                className="lt-btn-secondary"
                onClick={() => send({ type: 'checkForUpdates' })}
                style={{ padding: '6px 12px', fontSize: 12 }}
              >
                Check for Updates…
              </button>
            </SettingRow>
            <Divider />
            <SettingRow
              label="Backups"
              description="A database snapshot is taken before every upgrade and folder move, in Application Support → LocalTube → backups."
            >
              <span />
            </SettingRow>
          </div>
        </div>
      </div>

      {/* Save bar */}
      {(hasChanges || saved) && (
        <div style={{
          padding: '12px 24px',
          background: 'linear-gradient(135deg, rgba(255,255,255,0.09) 0%, rgba(255,255,255,0.06) 100%)',
          backgroundColor: 'rgba(13,13,15,0.85)',
          backdropFilter: 'blur(24px) saturate(180%)',
          WebkitBackdropFilter: 'blur(24px) saturate(180%)',
          borderTop: '0.5px solid rgba(255,255,255,0.1)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexShrink: 0,
        }}>
          <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
            {saved ? '✓ Settings saved' : 'You have unsaved changes'}
          </span>
          <div style={{ display: 'flex', gap: 8 }}>
            {!saved && (
              <button
                className="lt-btn-ghost"
                onClick={() => setLocal(pickEditable(settings))}
                style={{ fontSize: 13 }}
              >
                Revert
              </button>
            )}
            <button
              className="lt-btn-primary"
              onClick={handleSave}
              style={{ fontSize: 13, padding: '8px 16px' }}
            >
              {saved ? (
                <>
                  <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                    <path d="M2 6.5L5.5 10L11 3" stroke="white" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                  Saved
                </>
              ) : 'Save Settings'}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function ScanSummary({ scan }: { scan: LibraryScanResult }) {
  const when = scan.scannedAt ? new Date(scan.scannedAt) : null
  const problems = scan.missingFiles + scan.partialFiles + scan.orphanFiles + scan.errors.length
  const items: { label: string; value: string; tone?: 'ok' | 'warn' | 'bad' }[] = [
    { label: 'Downloaded', value: `${scan.readyVideos} / ${scan.totalVideos}` },
    { label: 'Paths repaired', value: String(scan.healedPaths + scan.bannersHealed), tone: scan.healedPaths + scan.bannersHealed > 0 ? 'ok' : undefined },
    { label: 'Missing files', value: scan.requeued > 0 ? `${scan.missingFiles} (${scan.requeued} re-queued)` : String(scan.missingFiles), tone: scan.missingFiles > 0 ? 'warn' : undefined },
    { label: 'Thumbnails rebuilt', value: String(scan.thumbnailsQueuedForRegeneration) },
    { label: 'Leftover partial files', value: String(scan.partialFiles), tone: scan.partialFiles > 0 ? 'warn' : undefined },
    { label: 'Unreferenced files', value: scan.orphanFiles > 0 ? `${scan.orphanFiles} (${formatBytes(scan.orphanBytes)})` : '0', tone: scan.orphanFiles > 0 ? 'warn' : undefined },
  ]
  return (
    <div style={{ padding: '14px 20px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10 }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: problems > 0 ? '#fde68a' : 'var(--success)' }}>
          {!scan.folderAvailable
            ? 'Library folder was not reachable'
            : problems > 0 ? 'Last scan found things to look at' : 'Last scan: everything in place'}
        </span>
        {when && (
          <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>{when.toLocaleString()}</span>
        )}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: '8px 16px' }}>
        {items.map(it => (
          <div key={it.label}>
            <div style={{ fontSize: 11, color: 'var(--text-tertiary)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>{it.label}</div>
            <div style={{
              fontSize: 14,
              fontWeight: 600,
              color: it.tone === 'bad' ? '#fca5a5' : it.tone === 'warn' ? '#fde68a' : it.tone === 'ok' ? 'var(--success)' : 'var(--text-primary)',
            }}>
              {it.value}
            </div>
          </div>
        ))}
      </div>
      {scan.errors.length > 0 && (
        <ul style={{ margin: '10px 0 0', paddingLeft: 18, fontSize: 12, color: '#fca5a5' }}>
          {scan.errors.map((e, i) => <li key={i}>{e}</li>)}
        </ul>
      )}
    </div>
  )
}

function DepStatus({ ok }: { ok: boolean }) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      padding: '4px 10px',
      borderRadius: 8,
      background: ok ? 'rgba(52,211,153,0.1)' : 'rgba(248,113,113,0.1)',
      border: `1px solid ${ok ? 'rgba(52,211,153,0.3)' : 'rgba(248,113,113,0.3)'}`,
    }}>
      <div style={{
        width: 7,
        height: 7,
        borderRadius: '50%',
        background: ok ? 'var(--success)' : 'var(--destructive)',
        boxShadow: `0 0 6px ${ok ? 'rgba(52,211,153,0.6)' : 'rgba(248,113,113,0.6)'}`,
      }} />
      <span style={{
        fontSize: 12,
        fontWeight: 600,
        color: ok ? 'var(--success)' : 'var(--destructive)',
      }}>
        {ok ? 'Installed' : 'Missing'}
      </span>
    </div>
  )
}
