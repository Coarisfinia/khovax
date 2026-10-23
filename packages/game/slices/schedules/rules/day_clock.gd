class_name DayClock
extends RefCounted
## The time of day in the rules (#1201): the smallest deterministic day clock, worked out from the
## world's tick alone (GameState.world_tick, #1215), which every instance holds and hashes, so it
## replays and resumes with it, and every instance of the world shows the same time: one nobody is
## in goes on with the rest, and walking through an exit never changes it. A day has HOURS hours of
## TICKS_PER_HOUR ticks each; it's day from DAWN until DUSK and night the rest. The world's first
## tick falls at dawn, so a fresh world starts in the morning.

## The hours of a day.
const HOURS: int = 24
## How many ticks an hour of the game's day lasts. A placeholder to tune (#960).
const TICKS_PER_HOUR: int = 30 * Simulation.TICKS_PER_SECOND
## The hour day breaks, and the hour night falls.
const DAWN: int = 6
const DUSK: int = 18


## The hour of the day (0 to HOURS - 1) it is now in `state`'s world (#1215).
static func hour_now(state: GameState) -> int:
	return hour_of(state.world_tick)


## The hour of the day (0 to HOURS - 1) the world's tick `tick` falls in.
static func hour_of(tick: int) -> int:
	return (DAWN + Fixed.div_floor(tick, TICKS_PER_HOUR)) % HOURS


## Whether `hour` is by day rather than at night.
static func is_day_hour(hour: int) -> bool:
	return hour >= DAWN and hour < DUSK
