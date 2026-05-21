import type { Profile } from '../types'
import { PROFILE_ICONS } from '../lib/profileIcons'
import { colorHex } from '../lib/profileColors'

/**
 * Profile visual identity. Render priority:
 *   1. icon + color → Phosphor icon on a soft circle of that color
 *   2. emoji        → emoji centered on a default gradient circle
 *   3. fallback     → first letter of name on a default gradient circle
 */
export default function ProfileAvatar({
  profile,
  size = 160,
}: {
  profile: Pick<Profile, 'name' | 'emoji' | 'icon' | 'color'>
  size?: number
}) {
  const iconName = profile.icon
  const IconComp = iconName ? PROFILE_ICONS[iconName] : undefined

  // Phosphor-icon style
  if (IconComp) {
    const bg = colorHex(profile.color)
    return (
      <div style={{
        width: size,
        height: size,
        borderRadius: size * 0.32,
        background: bg,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow: `0 8px 28px ${bg}40, 0 2px 6px rgba(0,0,0,0.25)`,
      }}>
        <IconComp
          size={size * 0.58}
          weight="fill"
          color="rgba(0,0,0,0.72)"
        />
      </div>
    )
  }

  // Emoji fallback
  if (profile.emoji) {
    return (
      <div style={{
        width: size,
        height: size,
        borderRadius: size * 0.2,
        background: 'linear-gradient(135deg, rgba(155,93,229,0.25) 0%, rgba(96,165,250,0.18) 100%)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: size * 0.52,
        boxShadow: '0 8px 28px rgba(0,0,0,0.35)',
      }}>
        <span>{profile.emoji}</span>
      </div>
    )
  }

  // First-letter fallback
  return (
    <div style={{
      width: size,
      height: size,
      borderRadius: size * 0.2,
      background: 'linear-gradient(135deg, rgba(155,93,229,0.25) 0%, rgba(96,165,250,0.18) 100%)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontSize: size * 0.42,
      fontWeight: 700,
      color: 'var(--text-primary)',
      boxShadow: '0 8px 28px rgba(0,0,0,0.35)',
    }}>
      {profile.name.charAt(0).toUpperCase()}
    </div>
  )
}
