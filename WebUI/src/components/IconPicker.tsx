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
      display: 'grid',
      gridTemplateColumns: 'repeat(8, 1fr)',
      gap: 8,
      maxHeight: 220,
      overflowY: 'auto',
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
              width: 44,
              height: 44,
              borderRadius: 10,
              background: selected ? color : 'rgba(255,255,255,0.04)',
              border: selected
                ? `1.5px solid ${color}`
                : '1px solid rgba(255,255,255,0.08)',
              cursor: 'pointer',
              transition: 'background 140ms ease, border-color 140ms ease, transform 140ms ease',
              padding: 0,
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
