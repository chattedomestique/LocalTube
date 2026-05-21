import {
  Heart, Star, Sparkle, Sun, Moon, Rainbow, Cloud, Lightning,
  Cat, Dog, Bird, Butterfly, Bug, Fish,
  Smiley, Ghost, Crown, Rocket, Robot, GameController,
  Pizza, IceCream, Cookie, Cake,
  TreeEvergreen, Flower, Leaf,
  HouseSimple, Car, Airplane,
  Camera, BookOpen, Headphones, Guitar,
  Basketball, SoccerBall,
  Diamond, Snowflake, FlowerLotus, Compass,
  type Icon,
} from '@phosphor-icons/react'

/**
 * Curated, kid-friendly subset of Phosphor icons used for profile avatars.
 * The key is the stable name we persist in the DB; the value is the React
 * component. Add to the end of the list — order is the picker grid order.
 *
 * Renderer (ProfileAvatar) looks up by key and falls back to emoji / first
 * letter if the key isn't recognised — safe across version bumps.
 */
export const PROFILE_ICONS: Record<string, Icon> = {
  Smiley,
  Heart,
  Star,
  Sparkle,
  Sun,
  Moon,
  Rainbow,
  Cloud,
  Lightning,
  Cat,
  Dog,
  Bird,
  Fish,
  Butterfly,
  Bug,
  Ghost,
  Crown,
  Rocket,
  Robot,
  GameController,
  Pizza,
  IceCream,
  Cookie,
  Cake,
  TreeEvergreen,
  Flower,
  FlowerLotus,
  Leaf,
  HouseSimple,
  Car,
  Airplane,
  Camera,
  BookOpen,
  Headphones,
  Guitar,
  Basketball,
  SoccerBall,
  Diamond,
  Snowflake,
  Compass,
}

export const PROFILE_ICON_NAMES = Object.keys(PROFILE_ICONS)
