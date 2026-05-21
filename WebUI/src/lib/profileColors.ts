/**
 * Twelve soft, parent-approved colors for profile avatars. Tuned to read
 * well on the app's dark background — saturated enough to feel cheerful,
 * desaturated enough not to clash with anything else on screen. The key
 * is what we persist; the hex is what we render.
 */
export const PROFILE_COLORS: { key: string; hex: string; label: string }[] = [
  { key: 'coral',      hex: '#FF8A80', label: 'Coral' },
  { key: 'peach',      hex: '#FFB088', label: 'Peach' },
  { key: 'apricot',    hex: '#FFCC80', label: 'Apricot' },
  { key: 'buttercream',hex: '#FFE082', label: 'Butter' },
  { key: 'sage',       hex: '#C5E1A5', label: 'Sage' },
  { key: 'mint',       hex: '#A5D6A7', label: 'Mint' },
  { key: 'teal',       hex: '#80CBC4', label: 'Teal' },
  { key: 'sky',        hex: '#81D4FA', label: 'Sky' },
  { key: 'blueberry',  hex: '#90CAF9', label: 'Blueberry' },
  { key: 'lavender',   hex: '#B39DDB', label: 'Lavender' },
  { key: 'plum',       hex: '#CE93D8', label: 'Plum' },
  { key: 'rose',       hex: '#F48FB1', label: 'Rose' },
]

export const DEFAULT_PROFILE_COLOR = 'lavender'

export function colorHex(key: string | undefined): string {
  if (!key) return PROFILE_COLORS.find(c => c.key === DEFAULT_PROFILE_COLOR)!.hex
  return PROFILE_COLORS.find(c => c.key === key)?.hex
    ?? PROFILE_COLORS.find(c => c.key === DEFAULT_PROFILE_COLOR)!.hex
}
