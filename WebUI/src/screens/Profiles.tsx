import { useState } from 'react'
import { useAppStore } from '../store'
import type { Profile } from '../types'

/**
 * Editor-mode screen for managing profiles. Lives under the Editor area;
 * reached from the Editor top bar. Lets parents create, rename,
 * re-emoji, delete profiles, and pick which channels each profile sees.
 */
export default function Profiles() {
  const { state, navigateTo, send } = useAppStore()
  const { profiles, channels, profileChannels } = state

  const sortedProfiles = [...profiles].sort((a, b) => a.sortOrder - b.sortOrder)
  const sortedChannels = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)

  const [selectedId, setSelectedId] = useState<string | null>(
    sortedProfiles[0]?.id ?? null
  )
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newEmoji, setNewEmoji] = useState('')
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [editEmoji, setEditEmoji] = useState('')

  const selected = sortedProfiles.find(p => p.id === selectedId) ?? sortedProfiles[0] ?? null
  const assigned = new Set(selected ? (profileChannels[selected.id] ?? []) : [])

  const handleAdd = () => {
    const trimmed = newName.trim()
    if (!trimmed) return
    send({ type: 'addProfile', payload: { name: trimmed, emoji: newEmoji || undefined } })
    setNewName('')
    setNewEmoji('')
    setShowAdd(false)
  }

  const handleEditStart = (p: Profile) => {
    setEditingId(p.id)
    setEditName(p.name)
    setEditEmoji(p.emoji ?? '')
  }

  const handleEditSave = () => {
    if (!editingId) return
    send({
      type: 'updateProfile',
      payload: { id: editingId, name: editName.trim(), emoji: editEmoji || '' },
    })
    setEditingId(null)
  }

  const handleDelete = (id: string) => {
    send({ type: 'deleteProfile', payload: { profileId: id } })
    setDeleteConfirmId(null)
    if (selectedId === id) {
      const remaining = sortedProfiles.filter(p => p.id !== id)
      setSelectedId(remaining[0]?.id ?? null)
    }
  }

  const toggleChannel = (channelId: string) => {
    if (!selected) return
    const current = new Set(profileChannels[selected.id] ?? [])
    if (current.has(channelId)) {
      current.delete(channelId)
    } else {
      current.add(channelId)
    }
    // Preserve channel sort order in the assignment list
    const ordered = sortedChannels.filter(c => current.has(c.id)).map(c => c.id)
    send({
      type: 'setProfileChannels',
      payload: { profileId: selected.id, channelIds: ordered },
    })
  }

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
        height: 52,
        borderBottom: '1px solid var(--border)',
        background: 'rgba(13,13,15,0.95)',
        backdropFilter: 'blur(12px)',
        flexShrink: 0,
        gap: 12,
      }}>
        <button
          className="lt-btn-ghost"
          onClick={() => navigateTo({ screen: 'editor' })}
          style={{ padding: '5px 10px', gap: 4, color: 'var(--text-secondary)', fontSize: 13 }}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path d="M9 2.5L4.5 7L9 11.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Editor
        </button>
        <div style={{ width: 1, height: 16, background: 'var(--border)' }} />
        <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--text-primary)' }}>Profiles</span>
        <div style={{ flex: 1 }} />
        <button
          className="lt-btn-primary"
          onClick={() => setShowAdd(true)}
          style={{ fontSize: 13, padding: '6px 12px' }}
        >
          <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
            <path d="M6.5 2V11M2 6.5H11" stroke="white" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
          New Profile
        </button>
      </div>

      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Sidebar: profile list */}
        <div style={{
          width: 260,
          borderRight: '1px solid var(--border)',
          background: 'var(--surface)',
          display: 'flex',
          flexDirection: 'column',
        }}>
          <div style={{ padding: '14px 14px 10px', borderBottom: '1px solid var(--border)' }}>
            <p className="lt-label">Profiles ({sortedProfiles.length})</p>
          </div>
          <div style={{ flex: 1, overflowY: 'auto', padding: 8 }}>
            {sortedProfiles.length === 0 ? (
              <div style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                padding: '32px 12px',
                gap: 8,
                textAlign: 'center',
              }}>
                <span style={{ fontSize: 32 }}>👤</span>
                <p style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                  No profiles yet
                </p>
                <button
                  className="lt-btn-primary"
                  onClick={() => setShowAdd(true)}
                  style={{ marginTop: 8, fontSize: 12 }}
                >
                  Create First Profile
                </button>
              </div>
            ) : (
              sortedProfiles.map(p => {
                const isSelected = p.id === selected?.id
                const isEditing = editingId === p.id
                const count = (profileChannels[p.id] ?? []).length
                return (
                  <div
                    key={p.id}
                    onClick={() => { setSelectedId(p.id); setEditingId(null) }}
                    style={{
                      padding: '8px 10px',
                      borderRadius: 9,
                      background: isSelected
                        ? 'var(--accent-dim)'
                        : 'transparent',
                      border: '1px solid',
                      borderColor: isSelected ? 'rgba(155,93,229,0.3)' : 'transparent',
                      marginBottom: 2,
                      cursor: 'pointer',
                      transition: 'background 140ms ease',
                    }}
                  >
                    {isEditing ? (
                      <div
                        onClick={e => e.stopPropagation()}
                        style={{ display: 'flex', flexDirection: 'column', gap: 6 }}
                      >
                        <div style={{ display: 'flex', gap: 6 }}>
                          <input
                            value={editEmoji}
                            onChange={e => setEditEmoji(e.target.value)}
                            maxLength={2}
                            placeholder="🙂"
                            style={{
                              width: 36,
                              fontSize: 18,
                              textAlign: 'center',
                              background: 'var(--surface-el)',
                              border: '1px solid var(--border)',
                              borderRadius: 6,
                              padding: '4px',
                              color: 'var(--text-primary)',
                            }}
                          />
                          <input
                            value={editName}
                            onChange={e => setEditName(e.target.value)}
                            onKeyDown={e => {
                              if (e.key === 'Enter') handleEditSave()
                              if (e.key === 'Escape') setEditingId(null)
                            }}
                            autoFocus
                            style={{
                              flex: 1,
                              fontSize: 13,
                              background: 'var(--surface-el)',
                              border: '1px solid var(--border)',
                              borderRadius: 6,
                              padding: '4px 8px',
                              color: 'var(--text-primary)',
                              outline: 'none',
                            }}
                          />
                        </div>
                        <div style={{ display: 'flex', gap: 5 }}>
                          <button className="lt-btn-xs primary" onClick={handleEditSave}>Save</button>
                          <button className="lt-btn-xs secondary" onClick={() => setEditingId(null)}>Cancel</button>
                        </div>
                      </div>
                    ) : (
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <span style={{ fontSize: 28 }}>{p.emoji || '🙂'}</span>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{
                            fontSize: 14,
                            fontWeight: 600,
                            color: isSelected ? 'var(--accent)' : 'var(--text-primary)',
                            whiteSpace: 'nowrap',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                          }}>
                            {p.name}
                          </div>
                          <div style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                            {count} channel{count !== 1 ? 's' : ''}
                          </div>
                        </div>
                        <div style={{ display: 'flex', gap: 2 }}>
                          <button
                            className="lt-row-btn"
                            onClick={e => { e.stopPropagation(); handleEditStart(p) }}
                            title="Rename"
                          >
                            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
                              <path d="M7.5 1.5L9 3L3.5 8.5H2V7L7.5 1.5Z" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round" fill="none" />
                            </svg>
                          </button>
                          <button
                            className="lt-row-btn destructive"
                            onClick={e => { e.stopPropagation(); setDeleteConfirmId(p.id) }}
                            title="Delete"
                          >
                            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
                              <path d="M2 3H9M3.5 3V2.5A.5.5 0 0 1 4 2H7A.5.5 0 0 1 7.5 2.5V3M4 5.5V8.5M7 5.5V8.5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
                              <path d="M2.5 3L3 9H8L8.5 3" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
                            </svg>
                          </button>
                        </div>
                      </div>
                    )}
                  </div>
                )
              })
            )}
          </div>
        </div>

        {/* Right panel: channel assignment */}
        <div style={{ flex: 1, overflowY: 'auto', padding: 20 }}>
          {selected ? (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 18 }}>
                <span style={{ fontSize: 36 }}>{selected.emoji || '🙂'}</span>
                <div>
                  <h2 style={{ fontSize: 22, marginBottom: 2 }}>{selected.name}'s channels</h2>
                  <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
                    {assigned.size} of {sortedChannels.length} selected
                  </p>
                </div>
              </div>

              {sortedChannels.length === 0 ? (
                <div style={{
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  padding: 60,
                  gap: 12,
                  textAlign: 'center',
                }}>
                  <span style={{ fontSize: 40 }}>📺</span>
                  <p style={{ fontSize: 14, color: 'var(--text-secondary)' }}>
                    No channels yet. Create some in the Channels editor first.
                  </p>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {sortedChannels.map(channel => {
                    const isAssigned = assigned.has(channel.id)
                    return (
                      <label
                        key={channel.id}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: 12,
                          padding: '10px 14px',
                          borderRadius: 10,
                          background: isAssigned ? 'var(--accent-dim)' : 'var(--surface)',
                          border: `1px solid ${isAssigned ? 'rgba(155,93,229,0.3)' : 'var(--border)'}`,
                          cursor: 'pointer',
                          transition: 'background 140ms ease, border-color 140ms ease',
                        }}
                      >
                        <input
                          type="checkbox"
                          checked={isAssigned}
                          onChange={() => toggleChannel(channel.id)}
                          style={{ width: 18, height: 18, accentColor: 'var(--accent)' }}
                        />
                        {channel.emoji && <span style={{ fontSize: 18 }}>{channel.emoji}</span>}
                        <span style={{
                          flex: 1,
                          fontSize: 14,
                          fontWeight: 600,
                          color: 'var(--text-primary)',
                        }}>
                          {channel.displayName}
                        </span>
                        <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                          {channel.type === 'source' ? '▶ Source' : '📂 Custom'}
                        </span>
                      </label>
                    )
                  })}
                </div>
              )}
            </>
          ) : (
            <div style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              gap: 14,
            }}>
              <span style={{ fontSize: 48 }}>👤</span>
              <h2 style={{ fontSize: 18 }}>No profile selected</h2>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', maxWidth: 320, textAlign: 'center' }}>
                Create a profile to control which channels different family members see.
              </p>
              <button className="lt-btn-primary" onClick={() => setShowAdd(true)}>
                Create First Profile
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Add profile modal */}
      {showAdd && (
        <div className="modal-backdrop" role="presentation">
          <div className="modal-panel" role="dialog" aria-modal="true" aria-label="New profile" style={{ width: 380, padding: 28 }}>
            <h2 style={{ fontSize: 18, marginBottom: 14 }}>New Profile</h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <div style={{ display: 'flex', gap: 8 }}>
                <input
                  value={newEmoji}
                  onChange={e => setNewEmoji(e.target.value)}
                  maxLength={2}
                  placeholder="🙂"
                  style={{
                    width: 56,
                    fontSize: 24,
                    textAlign: 'center',
                    background: 'var(--surface-el)',
                    border: '1px solid var(--border)',
                    borderRadius: 8,
                    padding: '8px',
                    color: 'var(--text-primary)',
                  }}
                />
                <input
                  value={newName}
                  onChange={e => setNewName(e.target.value)}
                  placeholder="Name (e.g. Alice)"
                  autoFocus
                  onKeyDown={e => {
                    if (e.key === 'Enter') handleAdd()
                    if (e.key === 'Escape') setShowAdd(false)
                  }}
                  style={{
                    flex: 1,
                    fontSize: 14,
                    background: 'var(--surface-el)',
                    border: '1px solid var(--border)',
                    borderRadius: 8,
                    padding: '10px 12px',
                    color: 'var(--text-primary)',
                    outline: 'none',
                  }}
                />
              </div>
              <p style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                You can pick which channels this profile sees after creating it.
              </p>
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 20 }}>
              <button
                className="lt-btn-secondary"
                onClick={() => { setShowAdd(false); setNewName(''); setNewEmoji('') }}
                style={{ flex: 1, justifyContent: 'center' }}
              >
                Cancel
              </button>
              <button
                className="lt-btn-primary"
                onClick={handleAdd}
                disabled={!newName.trim()}
                style={{ flex: 1, justifyContent: 'center' }}
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete profile confirm */}
      {deleteConfirmId && (() => {
        const p = profiles.find(p => p.id === deleteConfirmId)
        return p ? (
          <div className="modal-backdrop" role="presentation">
            <div className="modal-panel" role="dialog" aria-modal="true" aria-label="Confirm delete profile" style={{ width: 340, padding: 28 }}>
              <h2 style={{ fontSize: 16, marginBottom: 8 }}>Delete "{p.name}"?</h2>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 20 }}>
                The profile and its channel assignments will be removed. Channels and videos are not affected.
              </p>
              <div style={{ display: 'flex', gap: 8 }}>
                <button
                  className="lt-btn-secondary"
                  onClick={() => setDeleteConfirmId(null)}
                  style={{ flex: 1, justifyContent: 'center' }}
                >
                  Cancel
                </button>
                <button
                  className="lt-btn-destructive"
                  onClick={() => handleDelete(deleteConfirmId)}
                  style={{ flex: 1, justifyContent: 'center' }}
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        ) : null
      })()}
    </div>
  )
}
