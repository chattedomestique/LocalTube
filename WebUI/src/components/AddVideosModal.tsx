import type { FormEvent } from 'react'
import { useState } from 'react'

interface Props {
  channelName: string
  onAdd: (urls: string[]) => void
  onClose: () => void
}

function parseYouTubeUrls(text: string): string[] {
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0)
    .filter(line =>
      line.includes('youtube.com/watch') ||
      line.includes('youtu.be/') ||
      line.includes('youtube.com/shorts/')
    )
}

function isValidYouTubeUrl(url: string): boolean {
  return (
    url.includes('youtube.com/watch') ||
    url.includes('youtu.be/') ||
    url.includes('youtube.com/shorts/')
  )
}

export default function AddVideosModal({ channelName, onAdd, onClose }: Props) {
  const [input, setInput] = useState('')
  const [adding, setAdding] = useState(false)

  const lines = input.split('\n').map(l => l.trim()).filter(l => l.length > 0)
  const validUrls = lines.filter(isValidYouTubeUrl)
  const invalidCount = lines.length - validUrls.length

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    if (validUrls.length === 0) return
    setAdding(true)
    onAdd(validUrls)
    setAdding(false)
    onClose()
  }

  const handlePaste = async () => {
    try {
      const text = await navigator.clipboard.readText()
      setInput(prev => prev ? prev + '\n' + text : text)
    } catch {
      // Clipboard not available
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-panel"
        style={{ width: 520, padding: '28px' }}
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div style={{
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'space-between',
          marginBottom: 20,
        }}>
          <div>
            <h2 style={{ fontSize: 18, marginBottom: 4 }}>Add Videos</h2>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              Adding to <strong style={{ color: 'var(--text-primary)' }}>{channelName}</strong>
            </p>
          </div>
          <button
            className="lt-btn-ghost"
            onClick={onClose}
            style={{ padding: '6px 8px', color: 'var(--text-tertiary)' }}
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M3 3L13 13M13 3L3 13" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {/* URL input */}
          <div>
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: 8,
            }}>
              <label className="lt-label" style={{ marginBottom: 0 }}>YouTube URLs</label>
              <button
                type="button"
                className="lt-btn-ghost"
                onClick={handlePaste}
                style={{ padding: '3px 8px', fontSize: 12, gap: 4 }}
              >
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                  <rect x="3" y="3" width="7" height="8" rx="1.5" stroke="currentColor" strokeWidth="1.3" fill="none" />
                  <path d="M2 9V2H8" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                Paste from clipboard
              </button>
            </div>
            <textarea
              className="lt-input"
              value={input}
              onChange={e => setInput(e.target.value)}
              placeholder={"https://youtube.com/watch?v=dQw4w9WgXcQ\nhttps://youtube.com/watch?v=...\nhttps://youtu.be/..."}
              rows={8}
              style={{
                fontFamily: 'ui-monospace, Menlo, monospace',
                fontSize: 12,
                lineHeight: 1.8,
              }}
            />
          </div>

          {/* Validation feedback */}
          {lines.length > 0 && (
            <div style={{
              display: 'flex',
              gap: 12,
              padding: '10px 14px',
              borderRadius: 10,
              background: 'var(--surface-el)',
              border: '1px solid var(--border)',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <div style={{
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: validUrls.length > 0 ? 'var(--success)' : 'var(--text-tertiary)',
                  boxShadow: validUrls.length > 0 ? '0 0 6px rgba(52,211,153,0.5)' : 'none',
                }} />
                <span style={{
                  fontSize: 12,
                  color: validUrls.length > 0 ? 'var(--success)' : 'var(--text-tertiary)',
                  fontWeight: 600,
                }}>
                  {validUrls.length} valid URL{validUrls.length !== 1 ? 's' : ''}
                </span>
              </div>
              {invalidCount > 0 && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <div style={{
                    width: 8,
                    height: 8,
                    borderRadius: '50%',
                    background: 'var(--destructive)',
                    boxShadow: '0 0 6px rgba(248,113,113,0.5)',
                  }} />
                  <span style={{ fontSize: 12, color: 'var(--destructive)', fontWeight: 600 }}>
                    {invalidCount} skipped (not YouTube)
                  </span>
                </div>
              )}
            </div>
          )}

          {/* Helper note */}
          <p style={{
            fontSize: 12,
            color: 'var(--text-tertiary)',
            lineHeight: 1.6,
          }}>
            Paste one URL per line. Supports youtube.com/watch, youtu.be/, and Shorts links.
            Videos will be queued and downloaded in the background.
          </p>

          {/* Actions */}
          <div style={{ display: 'flex', gap: 10 }}>
            <button
              type="button"
              className="lt-btn-secondary"
              onClick={onClose}
              style={{ flex: 1, justifyContent: 'center' }}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="lt-btn-primary"
              disabled={validUrls.length === 0 || adding}
              style={{
                flex: 2,
                justifyContent: 'center',
                opacity: validUrls.length > 0 && !adding ? 1 : 0.4,
                cursor: validUrls.length > 0 && !adding ? 'pointer' : 'not-allowed',
              }}
            >
              {adding ? (
                <>
                  <svg className="spinner" width="13" height="13" viewBox="0 0 13 13" fill="none">
                    <circle cx="6.5" cy="6.5" r="5" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
                    <path d="M6.5 1.5A5 5 0 0 1 11.5 6.5" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
                  </svg>
                  Queuing...
                </>
              ) : (
                <>
                  <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                    <path d="M6.5 1.5v7M3.5 5.5l3 3 3-3" stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                    <path d="M1.5 10.5h10" stroke="white" strokeWidth="1.6" strokeLinecap="round" />
                  </svg>
                  Queue {validUrls.length} Download{validUrls.length !== 1 ? 's' : ''}
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
