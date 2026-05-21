import { useState } from 'react'
import { useAppStore } from '../store'
import type { Profile } from '../types'
import ProfileAvatar from '../components/ProfileAvatar'
import IconPicker from '../components/IconPicker'
import ColorPicker from '../components/ColorPicker'
import { colorHex, DEFAULT_PROFILE_COLOR } from '../lib/profileColors'

// Profiles tab content. The top bar (tabs + Exit) is provided by
// EditorShell — this component renders only the sidebar + detail body.

/**
 * Editor-mode screen for managing profiles. Lives under the Editor area;
 * reached from the Editor top bar. Lets parents create, customize
 * (icon + color), rename, delete profiles, and pick which channels each
 * profile sees.
 */
export default function Profiles() {
  const { state, send } = useAppStore()
  const { profiles, channels, profileChannels } = state

  const sortedProfiles = [...profiles].sort((a, b) => a.sortOrder - b.sortOrder)
  const sortedChannels = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)

  const [selectedId, setSelectedId] = useState<string | null>(
    sortedProfiles[0]?.id ?? null
  )
  const [showAdd, setShowAdd] = useState(false)
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)

  // Editor draft state for the inline rename/customize panel
  const [editName, setEditName] = useState('')
  const [editIcon, setEditIcon] = useState<string | undefined>(undefined)
  const [editColor, setEditColor] = useState<string>(DEFAULT_PROFILE_COLOR)

  // "Add profile" draft state
  const [newName, setNewName] = useState('')
  const [newIcon, setNewIcon] = useState<string | undefined>('Smiley')
  const [newColor, setNewColor] = useState<string>(DEFAULT_PROFILE_COLOR)

  const selected = sortedProfiles.find(p => p.id === selectedId) ?? sortedProfiles[0] ?? null
  const assigned = new Set(selected ? (profileChannels[selected.id] ?? []) : [])

  const handleAdd = () => {
    const trimmed = newName.trim()
    if (!trimmed) return
    send({
      type: 'addProfile',
      payload: {
        name: trimmed,
        icon: newIcon,
        color: newColor,
      },
    })
    setNewName('')
    setNewIcon('Smiley')
    setNewColor(DEFAULT_PROFILE_COLOR)
    setShowAdd(false)
  }

  const startEdit = (p: Profile) => {
    setEditingId(p.id)
    setEditName(p.name)
    setEditIcon(p.icon)
    setEditColor(p.color ?? DEFAULT_PROFILE_COLOR)
  }

  const saveEdit = () => {
    if (!editingId) return
    send({
      type: 'updateProfile',
      payload: {
        id: editingId,
        name: editName.trim(),
        icon: editIcon ?? '',
        color: editColor,
      },
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
    if (current.has(channelId)) current.delete(channelId)
    else current.add(channelId)
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
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Sidebar: profile list */}
        <div style={{
          width: 280,
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
                gap: 10,
                textAlign: 'center',
              }}>
                <span style={{ fontSize: 32 }}>👤</span>
                <p style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                  No profiles yet
                </p>
                <button
                  className="lt-btn-primary"
                  onClick={() => setShowAdd(true)}
                  style={{ marginTop: 6, fontSize: 12 }}
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
                      padding: '10px',
                      borderRadius: 10,
                      background: isSelected ? 'var(--accent-dim)' : 'transparent',
                      border: '1px solid',
                      borderColor: isSelected ? 'rgba(155,93,229,0.3)' : 'transparent',
                      marginBottom: 4,
                      cursor: 'pointer',
                      transition: 'background 140ms ease',
                    }}
                  >
                    {isEditing ? (
                      <div
                        onClick={e => e.stopPropagation()}
                        style={{ display: 'flex', flexDirection: 'column', gap: 10 }}
                      >
                        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                          <ProfileAvatar
                            profile={{ name: editName, icon: editIcon, color: editColor, emoji: undefined }}
                            size={48}
                          />
                          <input
                            value={editName}
                            onChange={e => setEditName(e.target.value)}
                            onKeyDown={e => {
                              if (e.key === 'Enter') saveEdit()
                              if (e.key === 'Escape') setEditingId(null)
                            }}
                            autoFocus
                            style={{
                              flex: 1,
                              fontSize: 14,
                              background: 'var(--surface-el)',
                              border: '1px solid var(--border)',
                              borderRadius: 6,
                              padding: '6px 10px',
                              color: 'var(--text-primary)',
                              outline: 'none',
                            }}
                          />
                        </div>
                        <ColorPicker value={editColor} onChange={setEditColor} />
                        <IconPicker
                          value={editIcon}
                          onChange={setEditIcon}
                          color={colorHex(editColor)}
                        />
                        <div style={{ display: 'flex', gap: 5 }}>
                          <button className="lt-btn-xs primary" onClick={saveEdit}>Save</button>
                          <button className="lt-btn-xs secondary" onClick={() => setEditingId(null)}>Cancel</button>
                        </div>
                      </div>
                    ) : (
                      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                        <ProfileAvatar profile={p} size={44} />
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
                            onClick={e => { e.stopPropagation(); startEdit(p) }}
                            title="Edit"
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
          {/* New Profile CTA — bottom of sidebar (replaces the top-bar
              "New Profile" button that lived on the old Profiles top bar). */}
          {sortedProfiles.length > 0 && (
            <div style={{ padding: '10px', borderTop: '1px solid var(--border)' }}>
              <button
                className="lt-btn-primary"
                onClick={() => setShowAdd(true)}
                style={{ width: '100%', justifyContent: 'center', fontSize: 13, padding: '9px 12px' }}
              >
                <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                  <path d="M6.5 2V11M2 6.5H11" stroke="white" strokeWidth="1.8" strokeLinecap="round" />
                </svg>
                New Profile
              </button>
            </div>
          )}
        </div>

        {/* Right panel: channel assignment */}
        <div style={{ flex: 1, overflowY: 'auto', padding: 20 }}>
          {selected ? (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 20 }}>
                <ProfileAvatar profile={selected} size={56} />
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
          <div className="modal-panel" role="dialog" aria-modal="true" aria-label="New profile" style={{ width: 460, padding: 32 }}>
            <h2 style={{ fontSize: 20, marginBottom: 18 }}>New Profile</h2>

            <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 18 }}>
              <ProfileAvatar
                profile={{ name: newName || '?', icon: newIcon, color: newColor, emoji: undefined }}
                size={72}
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
                  fontSize: 16,
                  background: 'var(--surface-el)',
                  border: '1px solid var(--border)',
                  borderRadius: 10,
                  padding: '12px 14px',
                  color: 'var(--text-primary)',
                  outline: 'none',
                }}
              />
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div>
                <p className="lt-label" style={{ marginBottom: 8 }}>Color</p>
                <ColorPicker value={newColor} onChange={setNewColor} />
              </div>
              <div>
                <p className="lt-label" style={{ marginBottom: 8 }}>Icon</p>
                <IconPicker value={newIcon} onChange={setNewIcon} color={colorHex(newColor)} />
              </div>
            </div>

            <div style={{ display: 'flex', gap: 8, marginTop: 22 }}>
              <button
                className="lt-btn-secondary"
                onClick={() => { setShowAdd(false); setNewName('') }}
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
