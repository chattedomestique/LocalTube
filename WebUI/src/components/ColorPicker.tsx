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
      // auto-fit + minmax = the grid sizes itself to ANY container width
      // without overflowing. The previous fixed-column version still
      // spilled out of the narrow sidebar (260 px) because 6 × 34 px +
      // 5 × 12 px gap = 264 px. With this layout the cells shrink to
      // fit and the swatches stay centered inside their cell.
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(34px, 1fr))',
      gap: 10,
      justifyItems: 'center',
      width: '100%',
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
              width: 30,
              height: 30,
              borderRadius: '50%',
              background: c.hex,
              border: selected
                ? '2.5px solid rgba(255,255,255,0.95)'
                : '1px solid rgba(255,255,255,0.18)',
              boxShadow: selected
                ? `0 0 0 3px ${c.hex}55, 0 4px 14px rgba(0,0,0,0.4)`
                : '0 1px 3px rgba(0,0,0,0.3)',
              cursor: 'pointer',
              transition: 'transform 180ms cubic-bezier(0.25,1,0.5,1), box-shadow 180ms ease, border-color 180ms ease',
              transform: selected ? 'scale(1.12)' : 'scale(1)',
              padding: 0,
            }}
            onMouseEnter={e => {
              if (!selected) e.currentTarget.style.transform = 'scale(1.08)'
            }}
            onMouseLeave={e => {
              if (!selected) e.currentTarget.style.transform = 'scale(1)'
            }}
          />
        )
      })}
    </div>
  )
}
