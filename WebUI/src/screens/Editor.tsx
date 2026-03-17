import { useState } from 'react'
import { useAppStore } from '../store'
import AddChannelModal from '../components/AddChannelModal'
import AddVideosModal from '../components/AddVideosModal'
import VideoCard from '../components/VideoCard'
import type { Channel, ChannelType } from '../types'

function formatTimer(seconds: number): string {
  if (seconds <= 0) return '0:00'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}

export default function Editor() {
  const { state, navigateTo, send } = useAppStore()
  const { channels, videos, editorRemainingSeconds, activeDownload } = state

  const [selectedChannelId, setSelectedChannelId] = useState<string | null>(
    channels[0]?.id ?? null
  )
  const [showAddChannel, setShowAddChannel] = useState(false)
  const [showAddVideos, setShowAddVideos] = useState(false)
  const [showExitConfirm, setShowExitConfirm] = useState(false)
  const [editingChannelId, setEditingChannelId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [editEmoji, setEditEmoji] = useState('')
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null)

  const sortedChannels = [...channels].sort((a, b) => a.sortOrder - b.sortOrder)
  const selectedChannel = channels.find(c => c.id === selectedChannelId) ?? sortedChannels[0] ?? null
  const selectedVideos = selectedChannel ? (videos[selectedChannel.id] ?? []) : []
  const sortedVideos = [...selectedVideos].sort((a, b) => a.sortOrder - b.sortOrder)

  const handleAddChannel = (data: {
    displayName: string
    emoji?: string
    type: ChannelType
    youtubeChannelId?: string
  }) => {
    send({ type: 'addChannel', payload: data })
    setShowAddChannel(false)
  }

  const handleAddVideos = (urls: string[]) => {
    if (!selectedChannel) return
    send({ type: 'addVideoURLs', payload: { channelId: selectedChannel.id, urls } })
    setShowAddVideos(false)
  }

  const handleDeleteChannel = (channelId: string) => {
    send({ type: 'deleteChannel', payload: { channelId } })
    if (selectedChannelId === channelId) {
      const remaining = sortedChannels.filter(c => c.id !== channelId)
      setSelectedChannelId(remaining[0]?.id ?? null)
    }
    setDeleteConfirmId(null)
  }

  const handleDeleteVideo = (videoId: string) => {
    send({ type: 'deleteVideo', payload: { videoId } })
  }

  const handleRetry = (videoId: string) => {
    send({ type: 'retryDownload', payload: { videoId } })
  }

  const handleEditStart = (channel: Channel) => {
    setEditingChannelId(channel.id)
    setEditName(channel.displayName)
    setEditEmoji(channel.emoji ?? '')
  }

  const handleEditSave = () => {
    if (!editingChannelId) return
    const channel = channels.find(c => c.id === editingChannelId)
    if (!channel) return
    send({ type: 'updateChannel', payload: { ...channel, displayName: editName.trim(), emoji: editEmoji || undefined } })
    setEditingChannelId(null)
  }

  const handleExitEditor = () => {
    send({ type: 'exitEditorMode' })
    navigateTo({ screen: 'library' })
  }

  const isUrgent = editorRemainingSeconds > 0 && editorRemainingSeconds <= 60

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
        {/* Back */}
        <button
          className="lt-btn-ghost"
          onClick={() => navigateTo({ screen: 'library' })}
          style={{ padding: '5px 10px', gap: 4, color: 'var(--text-secondary)', fontSize: 13 }}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path d="M9 2.5L4.5 7L9 11.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Library
        </button>
        <div style={{ width: 1, height: 16, background: 'var(--border)' }} />

        {/* Title */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 22,
            height: 22,
            borderRadius: 6,
            background: 'var(--accent-dim)',
            border: '1px solid rgba(155,93,229,0.3)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}>
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
              <path d="M9.5 1.5L10.5 2.5L3.5 9.5H2.5V8.5L9.5 1.5Z" stroke="var(--accent)" strokeWidth="1.3" strokeLinejoin="round" fill="none" />
            </svg>
          </div>
          <span style={{ fontSize: 14, fontWeight: 700, letterSpacing: '-0.01em', color: 'var(--accent)' }}>
            Editor Mode
          </span>
        </div>

        {/* Active download */}
        {activeDownload && (
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '3px 10px',
            borderRadius: 99,
            background: 'var(--surface-el)',
            border: '1px solid var(--border)',
          }}>
            <svg className="spinner" width="11" height="11" viewBox="0 0 11 11" fill="none">
              <circle cx="5.5" cy="5.5" r="4" stroke="rgba(255,255,255,0.2)" strokeWidth="1.5" />
              <path d="M5.5 1.5A4 4 0 0 1 9.5 5.5" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span style={{ fontSize: 11, color: 'var(--text-secondary)' }}>
              {Math.round(activeDownload.progress * 100)}%
            </span>
          </div>
        )}

        <div style={{ flex: 1 }} />

        {/* Timer */}
        {editorRemainingSeconds > 0 && (
          <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '4px 10px',
            borderRadius: 8,
            background: isUrgent ? 'rgba(248,113,113,0.1)' : 'var(--surface-el)',
            border: `1px solid ${isUrgent ? 'rgba(248,113,113,0.3)' : 'var(--border)'}`,
          }}>
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <circle cx="6" cy="6.5" r="4.5" stroke={isUrgent ? '#f87171' : 'var(--text-tertiary)'} strokeWidth="1.3" fill="none" />
              <path d="M6 4V6.5L7.5 8" stroke={isUrgent ? '#f87171' : 'var(--text-tertiary)'} strokeWidth="1.3" strokeLinecap="round" />
              <path d="M4.5 1.5H7.5" stroke={isUrgent ? '#f87171' : 'var(--text-tertiary)'} strokeWidth="1.3" strokeLinecap="round" />
            </svg>
            <span style={{
              fontSize: 12,
              fontWeight: 600,
              fontFamily: 'ui-monospace, monospace',
              color: isUrgent ? 'var(--destructive)' : 'var(--text-secondary)',
            }}>
              {formatTimer(editorRemainingSeconds)}
            </span>
          </div>
        )}

        {/* Exit editor */}
        <button
          className="lt-btn-secondary"
          onClick={() => setShowExitConfirm(true)}
          style={{ padding: '6px 12px', fontSize: 12 }}
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <rect x="2" y="5" width="8" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.3" fill="none" />
            <path d="M4 5V4C4 2.9 4.9 2 6 2C7.1 2 8 2.9 8 4V5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" fill="none" />
          </svg>
          Exit Editor
        </button>
      </div>

      {/* Body: sidebar + detail */}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Left sidebar */}
        <div style={{
          width: 240,
          borderRight: '1px solid var(--border)',
          display: 'flex',
          flexDirection: 'column',
          background: 'var(--surface)',
          flexShrink: 0,
        }}>
          <div style={{
            padding: '14px 14px 10px',
            borderBottom: '1px solid var(--border)',
          }}>
            <p className="lt-label">Channels</p>
          </div>

          {/* Channel list */}
          <div style={{ flex: 1, overflowY: 'auto', padding: '8px 8px' }}>
            {sortedChannels.length === 0 ? (
              <div style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                padding: '24px 12px',
                gap: 8,
                textAlign: 'center',
              }}>
                <span style={{ fontSize: 28 }}>📺</span>
                <p style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                  No channels yet
                </p>
              </div>
            ) : (
              sortedChannels.map(channel => {
                const channelVids = videos[channel.id] ?? []
                const isSelected = channel.id === selectedChannel?.id
                const isEditing = editingChannelId === channel.id

                return (
                  <div
                    key={channel.id}
                    onClick={() => { setSelectedChannelId(channel.id); setEditingChannelId(null) }}
                    style={{
                      padding: '8px 10px',
                      borderRadius: 9,
                      background: isSelected ? 'var(--accent-dim)' : 'transparent',
                      border: '1px solid',
                      borderColor: isSelected ? 'rgba(155,93,229,0.3)' : 'transparent',
                      marginBottom: 2,
                      cursor: 'pointer',
                      transition: 'all 0.12s ease',
                    }}
                  >
                    {isEditing ? (
                      <div
                        onClick={e => e.stopPropagation()}
                        style={{ display: 'flex', flexDirection: 'column', gap: 6 }}
                      >
                        <div style={{ display: 'flex', gap: 6 }}>
                          <input
                            style={{
                              width: 30,
                              fontSize: 16,
                              textAlign: 'center',
                              background: 'var(--surface-el)',
                              border: '1px solid var(--border)',
                              borderRadius: 6,
                              padding: '3px 4px',
                              color: 'var(--text-primary)',
                              flexShrink: 0,
                            }}
                            value={editEmoji}
                            onChange={e => setEditEmoji(e.target.value)}
                            maxLength={2}
                            placeholder="📺"
                          />
                          <input
                            style={{
                              flex: 1,
                              fontSize: 13,
                              background: 'var(--surface-el)',
                              border: '1px solid var(--border)',
                              borderRadius: 6,
                              padding: '3px 8px',
                              color: 'var(--text-primary)',
                              outline: 'none',
                            }}
                            value={editName}
                            onChange={e => setEditName(e.target.value)}
                            onKeyDown={e => {
                              if (e.key === 'Enter') handleEditSave()
                              if (e.key === 'Escape') setEditingChannelId(null)
                            }}
                            autoFocus
                          />
                        </div>
                        <div style={{ display: 'flex', gap: 5 }}>
                          <button
                            onClick={handleEditSave}
                            style={{
                              flex: 1,
                              fontSize: 11,
                              fontWeight: 600,
                              padding: '4px',
                              borderRadius: 5,
                              border: 'none',
                              background: 'var(--accent)',
                              color: 'white',
                              cursor: 'pointer',
                            }}
                          >
                            Save
                          </button>
                          <button
                            onClick={() => setEditingChannelId(null)}
                            style={{
                              flex: 1,
                              fontSize: 11,
                              padding: '4px',
                              borderRadius: 5,
                              border: '1px solid var(--border)',
                              background: 'transparent',
                              color: 'var(--text-secondary)',
                              cursor: 'pointer',
                            }}
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div style={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        {/* Drag handle */}
                        <svg
                          width="14"
                          height="14"
                          viewBox="0 0 14 14"
                          fill="none"
                          style={{ color: 'var(--text-tertiary)', flexShrink: 0, marginRight: 4 }}
                        >
                          <path d="M4.5 4.5h5M4.5 7h5M4.5 9.5h5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
                        </svg>

                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: 5,
                          }}>
                            {channel.emoji && (
                              <span style={{ fontSize: 14 }}>{channel.emoji}</span>
                            )}
                            <span style={{
                              fontSize: 13,
                              fontWeight: 600,
                              color: isSelected ? 'var(--accent)' : 'var(--text-primary)',
                              whiteSpace: 'nowrap',
                              overflow: 'hidden',
                              textOverflow: 'ellipsis',
                            }}>
                              {channel.displayName}
                            </span>
                          </div>
                          <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 1 }}>
                            {channelVids.length} video{channelVids.length !== 1 ? 's' : ''}
                          </div>
                        </div>

                        {/* Actions */}
                        <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
                          <button
                            onClick={(e) => { e.stopPropagation(); handleEditStart(channel) }}
                            style={{
                              width: 24,
                              height: 24,
                              borderRadius: 5,
                              border: 'none',
                              background: 'transparent',
                              color: 'var(--text-tertiary)',
                              cursor: 'pointer',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}
                            title="Rename"
                          >
                            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
                              <path d="M7.5 1.5L9 3L3.5 8.5H2V7L7.5 1.5Z" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round" fill="none" />
                            </svg>
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); setDeleteConfirmId(channel.id) }}
                            style={{
                              width: 24,
                              height: 24,
                              borderRadius: 5,
                              border: 'none',
                              background: 'transparent',
                              color: 'var(--text-tertiary)',
                              cursor: 'pointer',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}
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

          {/* Add channel button */}
          <div style={{ padding: '10px 10px', borderTop: '1px solid var(--border)' }}>
            <button
              className="lt-btn-primary"
              onClick={() => setShowAddChannel(true)}
              style={{ width: '100%', justifyContent: 'center', fontSize: 13, padding: '9px 12px' }}
            >
              <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                <path d="M6.5 2V11M2 6.5H11" stroke="white" strokeWidth="1.8" strokeLinecap="round" />
              </svg>
              New Channel
            </button>
          </div>
        </div>

        {/* Right panel: channel detail */}
        <div style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}>
          {selectedChannel ? (
            <>
              {/* Channel header */}
              <div style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '14px 20px',
                borderBottom: '1px solid var(--border)',
                flexShrink: 0,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  {selectedChannel.emoji && (
                    <span style={{ fontSize: 24 }}>{selectedChannel.emoji}</span>
                  )}
                  <div>
                    <h2 style={{ fontSize: 16, marginBottom: 2 }}>{selectedChannel.displayName}</h2>
                    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                      <span style={{
                        fontSize: 11,
                        padding: '2px 7px',
                        borderRadius: 99,
                        background: 'var(--surface-el)',
                        color: 'var(--text-tertiary)',
                        border: '1px solid var(--border)',
                      }}>
                        {selectedChannel.type === 'source' ? '▶ Source' : '📂 Custom'}
                      </span>
                      {selectedChannel.youtubeChannelId && (
                        <span style={{ fontSize: 11, color: 'var(--text-tertiary)', fontFamily: 'ui-monospace, monospace' }}>
                          {selectedChannel.youtubeChannelId}
                        </span>
                      )}
                      <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                        {sortedVideos.length} video{sortedVideos.length !== 1 ? 's' : ''}
                      </span>
                    </div>
                  </div>
                </div>

                <button
                  className="lt-btn-primary"
                  onClick={() => setShowAddVideos(true)}
                  style={{ fontSize: 13, padding: '7px 14px' }}
                >
                  <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                    <path d="M6.5 2V11M2 6.5H11" stroke="white" strokeWidth="1.8" strokeLinecap="round" />
                  </svg>
                  Add Videos
                </button>
              </div>

              {/* Video grid */}
              <div style={{ flex: 1, overflowY: 'auto', padding: '20px' }}>
                {sortedVideos.length === 0 ? (
                  <div style={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    height: '100%',
                    gap: 12,
                  }}>
                    <div style={{
                      width: 56,
                      height: 56,
                      borderRadius: 16,
                      background: 'var(--surface)',
                      border: '1px solid var(--border)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}>
                      <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
                        <rect x="2" y="4" width="20" height="16" rx="3" stroke="var(--text-tertiary)" strokeWidth="1.5" fill="none" />
                        <polygon points="10,9 17,12 10,15" fill="var(--text-tertiary)" />
                      </svg>
                    </div>
                    <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
                      No videos yet — add some YouTube URLs
                    </p>
                    <button
                      className="lt-btn-primary"
                      onClick={() => setShowAddVideos(true)}
                      style={{ fontSize: 13 }}
                    >
                      Add Videos
                    </button>
                  </div>
                ) : (
                  <div style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
                    gap: 12,
                  }}>
                    {sortedVideos.map(video => (
                      <VideoCard
                        key={video.id}
                        video={video}
                        isEditorMode={true}
                        isActiveDownload={activeDownload?.videoId === video.id}
                        onPlay={() => send({ type: 'playVideo', payload: { videoId: video.id } })}
                        onDelete={() => handleDeleteVideo(video.id)}
                        onRetry={() => handleRetry(video.id)}
                      />
                    ))}
                  </div>
                )}
              </div>
            </>
          ) : (
            // No channel selected
            <div style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              gap: 14,
            }}>
              <div style={{
                width: 64,
                height: 64,
                borderRadius: 18,
                background: 'var(--surface)',
                border: '1px solid var(--border)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}>
                <span style={{ fontSize: 28 }}>📺</span>
              </div>
              <h2 style={{ fontSize: 16 }}>Select a channel</h2>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', maxWidth: 280, textAlign: 'center' }}>
                Choose a channel from the sidebar, or create a new one to get started.
              </p>
              <button
                className="lt-btn-primary"
                onClick={() => setShowAddChannel(true)}
              >
                Create First Channel
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Modals */}
      {showAddChannel && (
        <AddChannelModal
          onAdd={handleAddChannel}
          onClose={() => setShowAddChannel(false)}
        />
      )}

      {showAddVideos && selectedChannel && (
        <AddVideosModal
          channelName={selectedChannel.displayName}
          onAdd={handleAddVideos}
          onClose={() => setShowAddVideos(false)}
        />
      )}

      {/* Delete channel confirm */}
      {deleteConfirmId && (() => {
        const ch = channels.find(c => c.id === deleteConfirmId)
        return ch ? (
          <div className="modal-backdrop">
            <div className="modal-panel" style={{ width: 340, padding: '28px' }}>
              <div style={{
                width: 48,
                height: 48,
                borderRadius: 14,
                background: 'rgba(248,113,113,0.1)',
                border: '1px solid rgba(248,113,113,0.25)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                marginBottom: 16,
              }}>
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
                  <path d="M3 5H17M6 5V4H14V5M8 9V15M12 9V15" stroke="#f87171" strokeWidth="1.8" strokeLinecap="round" />
                  <path d="M4 5L5 17H15L16 5" stroke="#f87171" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
              <h2 style={{ fontSize: 16, marginBottom: 8 }}>Delete "{ch.displayName}"?</h2>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 20 }}>
                All videos and downloaded files in this channel will be permanently deleted.
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
                  onClick={() => handleDeleteChannel(deleteConfirmId)}
                  style={{ flex: 1, justifyContent: 'center' }}
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        ) : null
      })()}

      {/* Exit editor confirm */}
      {showExitConfirm && (
        <div className="modal-backdrop">
          <div className="modal-panel" style={{ width: 320, padding: '28px' }}>
            <h2 style={{ fontSize: 16, marginBottom: 8 }}>Exit Editor Mode?</h2>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 20 }}>
              You'll need to enter your PIN again to re-enter editor mode.
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <button
                className="lt-btn-secondary"
                onClick={() => setShowExitConfirm(false)}
                style={{ flex: 1, justifyContent: 'center' }}
              >
                Stay
              </button>
              <button
                className="lt-btn-primary"
                onClick={handleExitEditor}
                style={{ flex: 1, justifyContent: 'center' }}
              >
                Exit
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
