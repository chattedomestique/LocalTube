import { PROFILE_COLORS } from '../lib/profileColors'

/**
 * Twelve-swatch color picker for profile avatars. Stores the color key
 * (e.g. "coral"); the hex lookup happens in ProfileAvatar.
 */
export default function ColorPicker({
  value,
  onChange,
}: {
  value: string | undefined
  onChange: (colorKey: string) => void
}) {
  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: 'repeat(12, 1fr)',
      gap: 6,
    }}>
      {PROFILE_COLORS.map(c => {
        const selected = value === c.key
        return (
          <button
            key={c.key}
            type="button"
            onClick={() => onChange(c.key)}
            title={c.label}
            aria-label={c.label}
            style={{
              width: 28,
              height: 28,
              borderRadius: '50%',
              background: c.hex,
              border: selected
                ? '2.5px solid rgba(255,255,255,0.95)'
                : '1px solid rgba(255,255,255,0.18)',
              boxShadow: selected
                ? `0 0 0 2px ${c.hex}55, 0 4px 12px rgba(0,0,0,0.4)`
                : '0 1px 3px rgba(0,0,0,0.3)',
              cursor: 'pointer',
              transition: 'transform 140ms cubic-bezier(0.25,1,0.5,1), box-shadow 140ms ease',
              transform: selected ? 'scale(1.12)' : 'scale(1)',
              padding: 0,
            }}
          />
        )
      })}
    </div>
  )
}
