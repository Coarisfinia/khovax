class_name Tuning
extends RefCounted
## The game's default balancing (#1309): every rule's number to tune, in this one file, so it's
## tweaked in one spot. The rules read them through their own constants, which point here. Every
## one is a placeholder to tune (#960). The numbers of a single content entry (a species' stats,
## an ability's power and cooldown, a loot table's weights, a gear's damage) stay in that entry's
## own file (#72). Changing a number here changes how the game plays: it needs a rules-change file
## (core/rules_changes/).
## Durations are in ticks (Simulation.TICKS_PER_SECOND a second), shares in thousandths (Fixed).
## In the core, since the core's World reads the instance reset delay and the core never names a
## slice; every slice may read it.

# The world.

## How long an instance nobody is in stays loaded before it's purged (#212): an hour of play,
## counted in the world's ticks, which only pass while the game is played, never while it's closed.
const INSTANCE_RESET_TICKS: int = 60 * 60 * Simulation.TICKS_PER_SECOND
## How many ticks an hour of the game's day lasts (#1201).
const TICKS_PER_HOUR: int = 30 * Simulation.TICKS_PER_SECOND
# Players.
## A player's HP: a few wild hits' worth (#455).
const PLAYER_HP: int = 500
## How much of their HP a revived player gets back, in thousandths: half (#479).
const REVIVED_HP: int = 500
## Ticks a player takes to walk from one tile to the next.
const MOVE_TICKS: int = 6
## How long an ally stands beside a knocked-down player to revive them (#479).
const REVIVE_TICKS: int = 3 * Simulation.TICKS_PER_SECOND
## How long a knocked-down player waits before going back to the spawn (#479).
const DOWN_TICKS: int = 30 * Simulation.TICKS_PER_SECOND
## How near an ally has to be for a fallen player to be knocked down rather than sent back (#479).
const ALLY_RANGE: int = 200
# Companions.
## The ticks between two strikes of one companion (#221).
const COMPANION_STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND
## How much of a species' stats (its HP plus twice its strength and its speed) widens a companion's
## reach by a tile (#338).
const COMPANION_STATS_PER_TILE: int = 120
## The reach of a species a companion wasn't given one for, and the shortest and longest any
## species has, in tiles (#338).
const COMPANION_LEAST_REACH: int = 1
const COMPANION_MOST_REACH: int = 5
## The shortest and longest rest between a companion's two roaming steps, in ticks (#338).
const COMPANION_LEAST_REST: int = 10
const COMPANION_MOST_REST: int = 40
## How much each level above 1 raises a companion's HP, strength and speed (its strikes come that
## much more often), in thousandths of its species' (#1255): a level 3 companion has 110% of each.
const COMPANION_GROWTH_PER_LEVEL: int = 50
## The ticks between two hurts of the trap's spikes, as between two auto attacks (#692).
const SPIKES_STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND
# Wild monsters.
## How much stronger each stack of rage makes a wild monster (thousandths), and the most stacks it
## takes (#220).
const RAGE_STRENGTH: int = 500
const MOST_RAGE: int = 3
## How much faster each stack of rage makes a wild monster (thousandths, #961): its steps and its
## strikes come this much more often.
const RAGE_SPEED: int = 500
## What each enraging heals, in thousandths of full HP (#220).
const ENRAGE_HEAL: int = 250
## How many ticks a wild monster that can't be ringed where it stands takes for each step away:
## its own pace, slower than a player's (#364).
const WILD_STEP_TICKS: int = Simulation.TICKS_PER_SECOND
## The share of its full HP a wild monster a region marks wounded starts with, in thousandths
## (#389).
const WOUNDED_HP: int = 250
## The ticks between two strikes of one wild monster, and how much a trail tile takes before it
## gives way (#422).
const WILD_STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND
const TILE_INTEGRITY: int = 400
## How many steps ahead a wild monster looks for its way (#1259).
const WAY_REACH: int = 10
## How far a hunter sees prey, how far from its home it roams, and how long it stalks one prey
## before it gives up (#1204).
const HUNT_SIGHT: int = 4
const HUNT_ROAM_RADIUS: int = 4
const HUNT_GIVE_UP_TICKS: int = 20 * Simulation.TICKS_PER_SECOND
## The most monsters in one pack, its leader included; how far from a leader the monsters it
## gathers stand when the instance begins; and how near its leader a member keeps (#1205).
const PACK_SIZE: int = 4
const PACK_REACH: int = 6
const PACK_KEEP_NEAR: int = 2
# Wild monsters' days (#1201).
## How many hours a diurnal or nocturnal monster sleeps in one block, and over how many hours after
## dusk (diurnal) or dawn (nocturnal) its bedtime is spread. A night or a day has room for both:
## its sleep never spills into its waking half.
const SLEEP_HOURS: int = 8
const BEDTIME_SPREAD: int = 3
## A cathemeral monster's bouts of sleep: one of BOUT_HOURS somewhere in every BOUT_SPAN hours of
## the day, a quarter of it.
const BOUT_HOURS: int = 2
const BOUT_SPAN: int = 6
## How many hours a day each need takes: a grazer's grazing, a drinker's drinking and a predator's
## hunting.
const GRAZE_HOURS: int = 3
const DRINK_HOURS: int = 2
const HUNT_HOURS: int = 3
# Rings and domination (#219).
## Players have no level yet: every player draws rings at this level until they do.
const PLAYER_LEVEL: int = 1
## Ring power is BASE + level × PER_LEVEL (+ companion passives, none yet): the issue's 100 + 20 ×
## level scaled up, so a monster's pressure each tick (its strength) wears a wall down over a
## whole seal rather than in one tick.
const RING_POWER_BASE: int = 30_000
const RING_POWER_PER_LEVEL: int = 6_000
## A seal takes this many ticks, plus one per SEAL_PRESSURE_PER_TICK of pressure inside
## (thousandths): more resistance seals slower.
const SEAL_BASE_TICKS: int = 40
const SEAL_PRESSURE_PER_TICK: int = 10 * Fixed.ONE
## The share of the pressure a wall segment takes while a player stands on it (thousandths, #227).
const REINFORCED_SHARE: int = 100
## The charges a placeholder totem starts with (#423).
const TOTEM_CHARGES: int = 3
# Loot.
## A domination's loot (#86): WALL_POINTS for each tile of the ring's wall a player colored, and
## one for every TICKS_PER_POINT ticks they stood on the wall while it sealed (#227); every
## POINTS_PER_ROLL points is a roll, up to FULL_ROLLS.
const WALL_POINTS: int = 2
const TICKS_PER_POINT: int = Simulation.TICKS_PER_SECOND
const POINTS_PER_ROLL: int = 3
const FULL_ROLLS: int = 3
## The rolls each player gets on a harvested monster's table (#629).
const HARVEST_ROLLS_PER_PLAYER: int = 1
## The rolls each player gets on the table when a chest opens or they find loot on the ground
## (#446, #203).
const CHEST_ROLLS_PER_PLAYER: int = 1
