import { PROFILE_ICONS, PROFILE_ICON_NAMES } from '../lib/profileIcons'

/**
 * Grid of selectable Phosphor icons for a profile avatar. Stores the icon
 * name (string key from PROFILE_ICONS) so we don't have to persist any
 * component reference.
 */
export default function IconPicker({
  value,
  onChange,
  color,
}: {
  value: string | undefined
  onChange: (iconName: string) => void
  /** Tint applied to the selected tile's halo so the picker echoes the
      chosen avatar color. */
  color: string
}) {
  return (
    <div style={{
      // auto-fit with a min width lets the grid size itself to the
      // container without ever overflowing horizontally. Vertical scroll
      // only — overflowX explicitly hidden so we never get the awful
      // both-axis scroll the previous fixed-column layout produced.
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(42px, 1fr))',
      gap: 8,
      maxHeight: 220,
      overflowY: 'auto',
      overflowX: 'hidden',
      padding: 4,
    }}>
      {PROFILE_ICON_NAMES.map(name => {
        const Icon = PROFILE_ICONS[name]
        const selected = value === name
        return (
          <button
            key={name}
            type="button"
            onClick={() => onChange(name)}
            title={name}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              aspectRatio: '1',
              borderRadius: 10,
              background: selected ? color : 'rgba(255,255,255,0.04)',
              border: selected
                ? `1.5px solid ${color}`
                : '1px solid rgba(255,255,255,0.08)',
              cursor: 'pointer',
              transition: 'background 160ms ease, border-color 160ms ease, transform 160ms cubic-bezier(0.25,1,0.5,1)',
              padding: 0,
            }}
            onMouseEnter={e => {
              if (!selected) {
                e.currentTarget.style.background = 'rgba(255,255,255,0.08)'
                e.currentTarget.style.transform = 'scale(1.06)'
              }
            }}
            onMouseLeave={e => {
              if (!selected) {
                e.currentTarget.style.background = 'rgba(255,255,255,0.04)'
                e.currentTarget.style.transform = 'scale(1)'
              }
            }}
          >
            <Icon
              size={22}
              weight="fill"
              color={selected ? 'rgba(0,0,0,0.78)' : 'rgba(255,255,255,0.85)'}
            />
          </button>
        )
      })}
    </div>
  )
}
