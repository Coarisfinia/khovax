class_name DayClock
extends RefCounted
## The time of day in the rules (#1201): the smallest deterministic day clock, worked out from the
## instance's tick alone, which the state already holds and hashes, so it replays and resumes with
## it. A day has HOURS hours of TICKS_PER_HOUR ticks each; it's day from DAWN until DUSK and night
## the rest. An instance's first tick falls at dawn, so a fresh instance starts in the morning. Each
## instance keeps its own tick, so its clock is its own too: one nobody is in stands still.

## The hours of a day.
const HOURS: int = 24
## How many ticks an hour of the game's day lasts. A placeholder to tune (#960).
const TICKS_PER_HOUR: int = 30 * Simulation.TICKS_PER_SECOND
## The hour day breaks, and the hour night falls.
const DAWN: int = 6
const DUSK: int = 18


## The hour of the day (0 to HOURS - 1) the instance's `tick` falls in.
static func hour_of(tick: int) -> int:
	return (DAWN + Fixed.div_floor(tick, TICKS_PER_HOUR)) % HOURS


## Whether `hour` is by day rather than at night.
static func is_day_hour(hour: int) -> bool:
	return hour >= DAWN and hour < DUSK
