class_name Schedule
extends RefCounted
## A wild monster's day (#1201), made from its species' behaviour traits (SpeciesBehaviour, owner's
## ground rule, #1199): one activity for every hour of the DayClock's day. Its sleep rhythm gives
## its sleep: a diurnal one sleeps one block at night, a nocturnal one one block by day, a
## cathemeral one in a bout in every quarter of the day, by day and at night, and a sleepless one
## never. Each of its needs then takes some of its waking hours, and it spends the rest following
## its pack if it bands with others, wandering if not. The behaviours themselves come in their own
## issues (#1202 to #1205); this is only when each one is due.

## No activity: what a monster without a schedule, or a fainted one, is doing.
const NONE: int = 0
const SLEEP: int = 1
const WANDER: int = 2
const GRAZE: int = 3
const DRINK: int = 4
const HUNT: int = 5
const FOLLOW_PACK: int = 6
## How many hours a diurnal or nocturnal monster sleeps in one block, and over how many hours after
## dusk (diurnal) or dawn (nocturnal) its bedtime is spread. A night or a day has room for both:
## its sleep never spills into its waking half. Their numbers are in Tuning (#1309).
const SLEEP_HOURS: int = Tuning.SLEEP_HOURS
const BEDTIME_SPREAD: int = Tuning.BEDTIME_SPREAD
## A cathemeral monster's bouts of sleep: one of BOUT_HOURS somewhere in every BOUT_SPAN hours of
## the
## day, a quarter of it. Their numbers are in Tuning (#1309).
const BOUT_HOURS: int = Tuning.BOUT_HOURS
const BOUT_SPAN: int = Tuning.BOUT_SPAN
## The activity each need fills its hours with, and how many hours a day it takes (its
## number is in Tuning, #1309).
const NEED_ACTIVITIES: Dictionary[String, int] = {
	SpeciesBehaviour.GRAZER: GRAZE,
	SpeciesBehaviour.DRINKER: DRINK,
	SpeciesBehaviour.PREDATOR: HUNT,
}
const NEED_HOURS: Dictionary[String, int] = {
	SpeciesBehaviour.GRAZER: Tuning.GRAZE_HOURS,
	SpeciesBehaviour.DRINKER: Tuning.DRINK_HOURS,
	SpeciesBehaviour.PREDATOR: Tuning.HUNT_HOURS,
}


## The day of a monster with the behaviour `traits` (its species', SpeciesBehaviour), one activity
## per hour from midnight, drawn from `rng`: when it goes to sleep and which waking hours its needs
## take. Traits without a rhythm or a need (a species the content doesn't know) give a day of
## wandering.
static func made(traits: Array, rng: Rng) -> Array[int]:
	var awake: int = WANDER
	if traits.has(SpeciesBehaviour.PACK_SPECIES) or traits.has(SpeciesBehaviour.PACK_TYPE):
		awake = FOLLOW_PACK
	var day: Array[int] = []
	for _hour: int in DayClock.HOURS:
		day.append(awake)
	if traits.has(SpeciesBehaviour.DIURNAL):
		_sleep(day, DayClock.DUSK + rng.below(BEDTIME_SPREAD), SLEEP_HOURS)
	elif traits.has(SpeciesBehaviour.NOCTURNAL):
		_sleep(day, DayClock.DAWN + rng.below(BEDTIME_SPREAD), SLEEP_HOURS)
	elif traits.has(SpeciesBehaviour.CATHEMERAL):
		for span: int in range(0, DayClock.HOURS, BOUT_SPAN):
			_sleep(day, span + rng.below(BOUT_SPAN - BOUT_HOURS + 1), BOUT_HOURS)
	var waking: Array[int] = []
	for hour: int in DayClock.HOURS:
		if day[hour] != SLEEP:
			waking.append(hour)
	# In the needs' fixed order, so the same traits always draw the same way.
	for need: String in SpeciesBehaviour.NEEDS:
		if not traits.has(need):
			continue
		for _slot: int in NEED_HOURS[need]:
			if waking.is_empty():
				break
			var hour: int = waking.pop_at(rng.below(waking.size()))
			day[hour] = NEED_ACTIVITIES[need]
	return day


## Marks `hours` hours of `day` asleep from `bedtime` on, wrapping past midnight.
static func _sleep(day: Array[int], bedtime: int, hours: int) -> void:
	for i: int in hours:
		day[(bedtime + i) % DayClock.HOURS] = SLEEP
