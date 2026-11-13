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


## The day of a monster with the behaviour `traits` (its species', SpeciesBehaviour) and the entity
## id `monster`, one activity per hour from midnight, with no roll (#2238): its id, modulo
## BEDTIME_SPREAD, is how many hours after dusk (diurnal) or dawn (nocturnal) it goes to sleep, so
## monsters of one species keep one rhythm without all sleeping at once; a cathemeral one starts
## each bout as many hours into its quarter of the day (modulo the room a quarter leaves). Its needs
## take evenly spaced hours of its waking day, counted from the hour it wakes (dawn plus the same
## offset for a sleepless one), taking turns in their fixed order. Traits without a rhythm or a
## need (a species the content doesn't know) give a day of wandering.
static func made(traits: Array, monster: int) -> Array[int]:
	var awake: int = WANDER
	if traits.has(SpeciesBehaviour.PACK_SPECIES) or traits.has(SpeciesBehaviour.PACK_TYPE):
		awake = FOLLOW_PACK
	var day: Array[int] = []
	for _hour: int in DayClock.HOURS:
		day.append(awake)
	var late: int = posmod(monster, BEDTIME_SPREAD)
	var wakes: int = DayClock.DAWN + late
	if traits.has(SpeciesBehaviour.DIURNAL):
		wakes = _sleep(day, DayClock.DUSK + late, SLEEP_HOURS)
	elif traits.has(SpeciesBehaviour.NOCTURNAL):
		wakes = _sleep(day, DayClock.DAWN + late, SLEEP_HOURS)
	elif traits.has(SpeciesBehaviour.CATHEMERAL):
		var into: int = posmod(monster, BOUT_SPAN - BOUT_HOURS + 1)
		for span: int in range(0, DayClock.HOURS, BOUT_SPAN):
			wakes = _sleep(day, span + into, BOUT_HOURS)
	var waking: Array[int] = []
	for i: int in DayClock.HOURS:
		var hour: int = (wakes + i) % DayClock.HOURS
		if day[hour] != SLEEP:
			waking.append(hour)
	var needs: Array[int] = _need_turns(traits)
	for slot: int in needs.size():
		day[waking[Fixed.mul_div(slot, waking.size(), needs.size())]] = needs[slot]
	return day


## The activities of the needs in `traits`, one per hour they take, taking turns in the needs'
## fixed order (graze, drink, graze, ...) until each has its hours.
static func _need_turns(traits: Array) -> Array[int]:
	var turns: Array[int] = []
	var most: int = 0
	for need: String in SpeciesBehaviour.NEEDS:
		most = maxi(most, NEED_HOURS[need])
	for turn: int in most:
		for need: String in SpeciesBehaviour.NEEDS:
			if traits.has(need) and turn < NEED_HOURS[need]:
				turns.append(NEED_ACTIVITIES[need])
	return turns


## Marks `hours` hours of `day` asleep from `bedtime` on, wrapping past midnight, and gives the hour
## it wakes.
static func _sleep(day: Array[int], bedtime: int, hours: int) -> int:
	for i: int in hours:
		day[(bedtime + i) % DayClock.HOURS] = SLEEP
	return (bedtime + hours) % DayClock.HOURS
