import type { FormEvent } from 'react'
import { useState } from 'react'
import type { ChannelType } from '../types'

interface Props {
  onAdd: (data: {
    displayName: string
    emoji?: string
    type: ChannelType
    youtubeChannelId?: string
  }) => void
  onClose: () => void
}

const EMOJI_SUGGESTIONS = ['📺', '🎬', '🎭', '🎮', '🎵', '📚', '🌍', '🔬', '💻', '🏋️', '🍳', '✈️', '🎨', '📰', '🤣']

export default function AddChannelModal({ onAdd, onClose }: Props) {
  const [displayName, setDisplayName] = useState('')
  const [emoji, setEmoji] = useState('')
  const [type, setType] = useState<ChannelType>('custom')
  const [youtubeChannelId, setYoutubeChannelId] = useState('')
  const [showEmojiPicker, setShowEmojiPicker] = useState(false)

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    if (!displayName.trim()) return
    onAdd({
      displayName: displayName.trim(),
      emoji: emoji || undefined,
      type,
      youtubeChannelId: type === 'source' && youtubeChannelId.trim()
        ? youtubeChannelId.trim()
        : undefined,
    })
  }

  const canSubmit = displayName.trim().length > 0

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-panel"
        style={{ width: 460, padding: '28px' }}
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: 24,
        }}>
          <div>
            <h2 style={{ fontSize: 18, marginBottom: 4 }}>New Channel</h2>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              Create a channel to organize your videos.
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

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          {/* Name + Emoji row */}
          <div>
            <label className="lt-label">Channel Name</label>
            <div style={{ display: 'flex', gap: 10 }}>
              {/* Emoji picker */}
              <div style={{ position: 'relative' }}>
                <button
                  type="button"
                  onClick={() => setShowEmojiPicker(!showEmojiPicker)}
                  style={{
                    width: 46,
                    height: 46,
                    borderRadius: 10,
                    border: '1px solid var(--border)',
                    background: 'var(--surface-el)',
                    fontSize: 22,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                    transition: 'all 0.15s ease',
                  }}
                >
                  {emoji || '📺'}
                </button>
                {showEmojiPicker && (
                  <div style={{
                    position: 'absolute',
                    top: 'calc(100% + 6px)',
                    left: 0,
                    zIndex: 200,
                    background: 'var(--surface-el)',
                    border: '1px solid var(--border)',
                    borderRadius: 12,
                    padding: 10,
                    display: 'flex',
                    flexWrap: 'wrap',
                    gap: 4,
                    width: 200,
                    boxShadow: 'var(--shadow-lg)',
                  }}>
                    {EMOJI_SUGGESTIONS.map(e => (
                      <button
                        key={e}
                        type="button"
                        onClick={() => { setEmoji(e); setShowEmojiPicker(false) }}
                        style={{
                          width: 32,
                          height: 32,
                          borderRadius: 7,
                          border: 'none',
                          background: emoji === e ? 'var(--accent-dim)' : 'transparent',
                          fontSize: 18,
                          cursor: 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          transition: 'background 0.1s ease',
                        }}
                        onMouseEnter={ev => { (ev.currentTarget as HTMLButtonElement).style.background = 'var(--surface)' }}
                        onMouseLeave={ev => { (ev.currentTarget as HTMLButtonElement).style.background = emoji === e ? 'var(--accent-dim)' : 'transparent' }}
                      >
                        {e}
                      </button>
                    ))}
                    <button
                      type="button"
                      onClick={() => { setEmoji(''); setShowEmojiPicker(false) }}
                      style={{
                        width: '100%',
                        borderRadius: 7,
                        border: 'none',
                        background: 'transparent',
                        color: 'var(--text-tertiary)',
                        fontSize: 11,
                        cursor: 'pointer',
                        padding: '4px',
                        marginTop: 4,
                      }}
                    >
                      Clear emoji
                    </button>
                  </div>
                )}
              </div>

              <input
                className="lt-input"
                type="text"
                placeholder="e.g. Tech Talks, Cooking, etc."
                value={displayName}
                onChange={e => setDisplayName(e.target.value)}
                autoFocus
                style={{ height: 46 }}
              />
            </div>
          </div>

          {/* Channel type */}
          <div>
            <label className="lt-label">Channel Type</label>
            <div style={{ display: 'flex', gap: 8 }}>
              {([
                { value: 'custom', label: 'Custom', desc: 'Manually curated videos', icon: '📂' },
                { value: 'source', label: 'YouTube Source', desc: 'Synced from a channel', icon: '▶️' },
              ] as const).map(opt => (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => setType(opt.value)}
                  style={{
                    flex: 1,
                    padding: '12px 14px',
                    borderRadius: 10,
                    border: '1px solid',
                    borderColor: type === opt.value ? 'var(--accent)' : 'var(--border)',
                    background: type === opt.value ? 'var(--accent-dim)' : 'var(--surface-el)',
                    cursor: 'pointer',
                    textAlign: 'left',
                    transition: 'all 0.15s ease',
                    boxShadow: type === opt.value ? '0 0 0 2px var(--accent-dim)' : 'none',
                  }}
                >
                  <div style={{ fontSize: 18, marginBottom: 4 }}>{opt.icon}</div>
                  <div style={{
                    fontSize: 13,
                    fontWeight: 600,
                    color: type === opt.value ? 'var(--accent)' : 'var(--text-primary)',
                    marginBottom: 2,
                  }}>
                    {opt.label}
                  </div>
                  <div style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                    {opt.desc}
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* YouTube channel ID (source only) */}
          {type === 'source' && (
            <div>
              <label className="lt-label">YouTube Channel ID</label>
              <input
                className="lt-input"
                type="text"
                placeholder="@ChannelHandle or UCxxxxxxxxxxxxxxxxxx"
                value={youtubeChannelId}
                onChange={e => setYoutubeChannelId(e.target.value)}
              />
              <p style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 5 }}>
                Found in the channel URL on YouTube.com
              </p>
            </div>
          )}

          {/* Actions */}
          <div style={{ display: 'flex', gap: 10, marginTop: 4 }}>
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
              disabled={!canSubmit}
              style={{
                flex: 2,
                justifyContent: 'center',
                opacity: canSubmit ? 1 : 0.4,
                cursor: canSubmit ? 'pointer' : 'not-allowed',
              }}
            >
              Create Channel
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
