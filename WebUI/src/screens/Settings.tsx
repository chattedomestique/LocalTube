import type { ReactNode } from 'react'
import { useState, useEffect } from 'react'
import { useAppStore } from '../store'
import type { AppSettings } from '../types'

const QUALITY_OPTIONS = [
  { value: 'best',     label: 'Best Available' },
  { value: '1080p',    label: '1080p (Full HD)' },
  { value: '720p',     label: '720p (HD)' },
  { value: '480p',     label: '480p (SD)' },
  { value: '360p',     label: '360p (Low)' },
  { value: 'audio',    label: 'Audio Only' },
]

const AUTO_LOCK_OPTIONS = [5, 10, 15, 30, 60]

function SettingRow({
  label,
  description,
  children,
}: {
  label: string
  description?: string
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
      <div>
        <div style={{
          fontSize: 14,
          fontWeight: 500,
          color: 'var(--text-primary)',
          marginBottom: description ? 3 : 0,
        }}>
          {label}
        </div>
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
  return <div style={{ height: 1, background: 'var(--border)', margin: '0 20px' }} />
}

export default function Settings() {
  const { state, navigateTo, send, setOnFolderSelected } = useAppStore()
  const { settings, dependencyStatus } = state
  const [local, setLocal] = useState<AppSettings>({ ...settings })
  const [saved, setSaved] = useState(false)
  const [checkingDeps, setCheckingDeps] = useState(false)

  useEffect(() => {
    setLocal({ ...settings })
  }, [settings])

  useEffect(() => {
    setOnFolderSelected((path: string) => {
      setLocal(prev => ({ ...prev, downloadFolderPath: path }))
    })
    return () => setOnFolderSelected(undefined)
  }, [setOnFolderSelected])

  const handleSave = () => {
    send({ type: 'saveSettings', payload: local })
    setSaved(true)
    setTimeout(() => setSaved(false), 2000)
  }

  const handleChangePath = () => {
    send({ type: 'openFolderPicker' })
  }

  const handleCheckDeps = () => {
    setCheckingDeps(true)
    send({ type: 'checkDependencies' })
    setTimeout(() => setCheckingDeps(false), 3000)
  }

  const hasChanges = JSON.stringify(local) !== JSON.stringify(settings)

  return (
    <div className="screen-enter" style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: 'var(--bg)',
    }}>
      {/* Top bar */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        padding: '0 20px',
        height: 56,
        borderBottom: '1px solid var(--border)',
        background: 'rgba(13,13,15,0.9)',
        backdropFilter: 'blur(12px)',
        flexShrink: 0,
        gap: 12,
      }}>
        <button
          className="lt-btn-ghost"
          onClick={() => navigateTo({ screen: 'library' })}
          style={{ padding: '6px 10px', gap: 4, color: 'var(--text-secondary)' }}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M10 3L5 8L10 13" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Library
        </button>
        <div style={{ width: 1, height: 18, background: 'var(--border)' }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <circle cx="8" cy="8" r="2.5" stroke="var(--text-secondary)" strokeWidth="1.5" />
            <path d="M8 1.5V3M8 13V14.5M14.5 8H13M3 8H1.5M12.95 3.05l-.95.95M4 12l-.95.95M12.95 12.95l-.95-.95M4 4l-.95-.95" stroke="var(--text-secondary)" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
          <h1 style={{ fontSize: 16, fontWeight: 700 }}>Settings</h1>
        </div>
      </div>

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
        {/* Downloads section */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>Downloads</p>
          <div style={{
            background: 'var(--surface)',
            border: '1px solid var(--border)',
            borderRadius: 14,
            overflow: 'hidden',
          }}>
            <SettingRow
              label="Download Folder"
              description="Where LocalTube saves video files"
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                {local.downloadFolderPath && (
                  <span style={{
                    fontSize: 12,
                    color: 'var(--text-secondary)',
                    fontFamily: 'ui-monospace, monospace',
                    maxWidth: 180,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}>
                    {local.downloadFolderPath.split('/').pop() ?? local.downloadFolderPath}
                  </span>
                )}
                <button
                  className="lt-btn-secondary"
                  onClick={handleChangePath}
                  style={{ padding: '6px 12px', fontSize: 12 }}
                >
                  Change
                </button>
              </div>
            </SettingRow>

            <Divider />

            <SettingRow
              label="Download Quality"
              description="Default quality for new downloads"
            >
              <select
                className="lt-input"
                value={local.downloadQuality}
                onChange={e => setLocal(prev => ({ ...prev, downloadQuality: e.target.value }))}
                style={{ width: 180, padding: '7px 32px 7px 12px' }}
              >
                {QUALITY_OPTIONS.map(opt => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </SettingRow>
          </div>
        </div>

        {/* Editor section */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>Editor</p>
          <div style={{
            background: 'var(--surface)',
            border: '1px solid var(--border)',
            borderRadius: 14,
            overflow: 'hidden',
          }}>
            <SettingRow
              label="Auto-Lock Editor After"
              description="Automatically lock editor mode after inactivity"
            >
              <select
                className="lt-input"
                value={local.editorAutoLockMinutes}
                onChange={e => setLocal(prev => ({ ...prev, editorAutoLockMinutes: Number(e.target.value) }))}
                style={{ width: 160, padding: '7px 32px 7px 12px' }}
              >
                {AUTO_LOCK_OPTIONS.map(n => (
                  <option key={n} value={n}>
                    {n < 60 ? `${n} minutes` : '1 hour'}
                  </option>
                ))}
              </select>
            </SettingRow>
          </div>
        </div>

        {/* Dependencies section */}
        <div>
          <p className="lt-label" style={{ marginBottom: 10 }}>Dependencies</p>
          <div style={{
            background: 'var(--surface)',
            border: '1px solid var(--border)',
            borderRadius: 14,
            overflow: 'hidden',
          }}>
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
          <div style={{
            background: 'var(--surface)',
            border: '1px solid var(--border)',
            borderRadius: 14,
            overflow: 'hidden',
          }}>
            <SettingRow label="LocalTube" description="Your offline YouTube library">
              <span style={{ fontSize: 12, color: 'var(--text-tertiary)', fontFamily: 'ui-monospace, monospace' }}>
                v1.0.0
              </span>
            </SettingRow>
          </div>
        </div>
      </div>

      {/* Save bar */}
      {(hasChanges || saved) && (
        <div style={{
          padding: '12px 24px',
          borderTop: '1px solid var(--border)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          background: 'var(--surface)',
          flexShrink: 0,
        }}>
          <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
            {saved ? '✓ Settings saved' : 'You have unsaved changes'}
          </span>
          <div style={{ display: 'flex', gap: 8 }}>
            {!saved && (
              <button
                className="lt-btn-ghost"
                onClick={() => setLocal({ ...settings })}
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
