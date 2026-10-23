extends RefCounted
## Behaviour flow (#1199): wild monsters live by their species' behaviour traits. The day clock
## (#1201) follows the tick: an instance starts at dawn, night falls at dusk, and a day later it's
## dawn again. Every wild monster gets a daily schedule from its traits and the instance's seed:
## a diurnal one sleeps one block at night, a nocturnal one one block by day, a cathemeral one in
## bouts by day and at night, a sleepless one never; each need takes its hours, and the rest it
## follows its pack, or wanders without one. What it's doing now follows the clock, and a fainted
## one does nothing. The schedules are the same for the same seed, differ for another, are in the
## state hash and come back the same from a save. The content's own species, the nocturnal
## Ombulumo and the diurnal Tikazzir, follow theirs in an instance the blueprints make.

## A test species of each sleep rhythm, with needs and bands that cover every activity.
const TEST_TRAITS: Dictionary[String, Array] = {
	"diu": ["diurnal", "grazer", "drinker"],
	"noc": ["nocturnal", "predator", "pack_species"],
	"cat": ["cathemeral", "grazer", "pack_type"],
	"sle": ["sleepless", "drinker", "predator"],
}
const SEED: int = 42
## The content species the flow checks, which the blueprints' basic instance places.
const CONTENT_SPECIES: Array[String] = ["ombulumo", "tikazzir"]


func run(_tree: SceneTree) -> String:
	var steps: Array[Callable] = [
		_check_day_clock,
		_check_rhythms,
		_check_activity_follows_clock,
		_check_deterministic,
		_check_content_species,
	]
	for check: Callable in steps:
		var result: String = check.call()
		if not result.is_empty():
			return result
	return ""


## The clock starts at dawn, turns to night at dusk, and comes back to dawn a day later.
func _check_day_clock() -> String:
	var dusk: int = (DayClock.DUSK - DayClock.DAWN) * DayClock.TICKS_PER_HOUR
	var day: int = DayClock.HOURS * DayClock.TICKS_PER_HOUR
	if DayClock.hour_of(0) != DayClock.DAWN or not DayClock.is_day_hour(DayClock.hour_of(0)):
		return "an instance didn't start at dawn"
	if DayClock.hour_of(DayClock.TICKS_PER_HOUR - 1) != DayClock.DAWN:
		return "the clock turned before an hour was up"
	if DayClock.hour_of(dusk) != DayClock.DUSK or DayClock.is_day_hour(DayClock.hour_of(dusk)):
		return "night didn't fall at dusk"
	if not DayClock.is_day_hour(DayClock.hour_of(dusk - 1)):
		return "night fell before dusk"
	if DayClock.hour_of(day) != DayClock.DAWN or DayClock.hour_of(day + dusk) != DayClock.DUSK:
		return "the next day didn't run like the first"
	return ""


## Each test species' monster follows its rhythm, needs and bands.
func _check_rhythms() -> String:
	var state: GameState = _test_state(SEED, TEST_TRAITS)
	var schedules: ScheduleFeature = _schedules(state)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild.monsters.size() != TEST_TRAITS.size():
		return "the test region placed %d wild monsters" % wild.monsters.size()
	for monster: int in wild.monsters:
		var species: String = wild.species_of(monster)
		var problem: String = _day_problem(schedules.day_of(monster), TEST_TRAITS[species])
		if not problem.is_empty():
			return "%s's day: %s" % [species, problem]
	return ""


## What a monster is doing now is its schedule's activity for the clock's hour, hour after hour of
## a whole day, across a real tick too; a fainted one does nothing.
func _check_activity_follows_clock() -> String:
	var state: GameState = _test_state(SEED, TEST_TRAITS)
	var schedules: ScheduleFeature = _schedules(state)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in wild.monsters:
		var day: Array[int] = schedules.day_of(monster)
		for hour: int in DayClock.HOURS:
			var from_dawn: int = (hour - DayClock.DAWN + DayClock.HOURS) % DayClock.HOURS
			state.tick = from_dawn * DayClock.TICKS_PER_HOUR
			if schedules.activity_of(state, monster) != day[hour]:
				return "monster %d didn't do at %d o'clock what its day says" % [monster, hour]
	var first: int = wild.monsters[0]
	var first_day: Array[int] = schedules.day_of(first)
	state.tick = DayClock.TICKS_PER_HOUR - 1
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if schedules.activity_of(state, first) != first_day[DayClock.DAWN + 1]:
		return "a tick past the hour didn't bring the next hour's activity"
	wild.wound(state, first, Fixed.MAX_AMOUNT, true)
	if not wild.is_fainted(first) or schedules.activity_of(state, first) != Schedule.NONE:
		return "a fainted wild monster still keeps to its schedule"
	return ""


## The same seed makes the same schedules, another seed others; they're in the state hash, and a
## save, taken after one fainted, gives them back the same.
func _check_deterministic() -> String:
	var state: GameState = _test_state(SEED, TEST_TRAITS)
	var again: GameState = _test_state(SEED, TEST_TRAITS)
	if _days(state) != _days(again) or state.state_hash() != again.state_hash():
		return "the same seed made other schedules"
	if _days(_test_state(SEED + 1, TEST_TRAITS)) == _days(state):
		return "another seed made the same schedules"
	var other: Dictionary[String, Array] = {}
	for species: String in TEST_TRAITS:
		other[species] = TEST_TRAITS["noc"] if species == "diu" else TEST_TRAITS[species]
	if _test_state(SEED, other).state_hash() == state.state_hash():
		return "another rhythm left the state hash as it was"
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	wild.wound(state, wild.monsters[0], Fixed.MAX_AMOUNT, true)
	var loaded: GameState = _test_state(SEED, TEST_TRAITS)
	loaded.load_data(DataReader.new(state.to_data()))
	if _days(loaded) != _days(state) or loaded.state_hash() != state.state_hash():
		return "a save didn't give the schedules back the same"
	return ""


## The content's Ombulumo and Tikazzir, built by the factories from their species data, follow
## their traits, and the blueprints' basic instance, which places wild monsters, has schedules.
func _check_content_species() -> String:
	var setup: FeatureSetup = FeatureSetup.new()
	var region: Region = _region(CONTENT_SPECIES)
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFactory.build(setup),
		WildMonsterFactory.build(setup),
		ScheduleFactory.build(setup),
	]
	var state: GameState = GameState.new(region, SEED, ordered)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var content: SpeciesContent = SpeciesContent.cached()
	for monster: int in wild.monsters:
		var species: Species = content.species[wild.species_of(monster)]
		var problem: String = _day_problem(_schedules(state).day_of(monster), species.behaviour)
		if not problem.is_empty():
			return "%s's day: %s" % [species.id, problem]
	var basic: GameState = FlowSteps.basic(SEED)
	if basic.feature(ScheduleFeature.ID) == null:
		return "the basic instance's wild monsters have no schedules"
	var basic_wild: WildMonsterFeature = basic.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in basic_wild.monsters:
		if (basic.feature(ScheduleFeature.ID) as ScheduleFeature).day_of(monster).is_empty():
			return "the basic instance's wild monster %d has no day" % monster
	return ""


## Why `day` doesn't follow `traits`, or "": its sleep by its rhythm, each need's hours, and the
## rest following its pack if it bands, wandering if not.
static func _day_problem(day: Array[int], traits: Array) -> String:
	if day.size() != DayClock.HOURS:
		return "it has %d hours" % day.size()
	var problem: String = _sleep_problem(day, traits)
	if not problem.is_empty():
		return problem
	var busy: int = day.count(Schedule.SLEEP)
	for need: String in Schedule.NEED_ACTIVITIES:
		var hours: int = Schedule.NEED_HOURS[need] if traits.has(need) else 0
		var spent: int = day.count(Schedule.NEED_ACTIVITIES[need])
		if spent != hours:
			return "its need %s took %d hours, not %d" % [need, spent, hours]
		busy += hours
	var bands: bool = (traits.has(SpeciesBehaviour.PACK_SPECIES)
			or traits.has(SpeciesBehaviour.PACK_TYPE))
	var rest: int = Schedule.FOLLOW_PACK if bands else Schedule.WANDER
	if day.count(rest) != DayClock.HOURS - busy:
		return "it spent %d hours on %d, not the %d it had left" % [
			day.count(rest),
			rest,
			DayClock.HOURS - busy,
		]
	return ""


## Why `day`'s sleep doesn't follow the rhythm in `traits`, or "": a diurnal one sleeps one block
## at night, a nocturnal one one block by day, a cathemeral one in bouts both by day and at night,
## a sleepless one never.
static func _sleep_problem(day: Array[int], traits: Array) -> String:
	var sleep: Array[int] = [0, 0]
	for hour: int in DayClock.HOURS:
		if day[hour] == Schedule.SLEEP:
			sleep[0 if DayClock.is_day_hour(hour) else 1] += 1
	if traits.has(SpeciesBehaviour.CATHEMERAL):
		var bouts: int = Fixed.div_floor(DayClock.HOURS, Schedule.BOUT_SPAN)
		if sleep[0] == 0 or sleep[1] == 0 or sleep[0] + sleep[1] != bouts * Schedule.BOUT_HOURS:
			return "a cathemeral one slept %s hours by day and at night" % [sleep]
		return ""
	var expected: Array[int] = [0, 0]
	if traits.has(SpeciesBehaviour.DIURNAL):
		expected = [0, Schedule.SLEEP_HOURS]
	elif traits.has(SpeciesBehaviour.NOCTURNAL):
		expected = [Schedule.SLEEP_HOURS, 0]
	if sleep != expected:
		return "it slept %s hours by day and at night, not %s" % [sleep, expected]
	return ""


## A disc with one wild monster of every test species, the schedules built from `traits`.
static func _test_state(seed_value: int, traits: Dictionary[String, Array]) -> GameState:
	var species: Array[String] = []
	species.assign(TEST_TRAITS.keys())
	var health: Dictionary[String, int] = {}
	for each: String in species:
		health[each] = 10
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(health),
		WildMonsterFeature.new([], [], {}),
		ScheduleFeature.new(traits),
	]
	return GameState.new(_region(species), seed_value, ordered)


## A disc with a wild monster of each of `species` in a row, each named by its spot.
static func _region(species: Array[String]) -> Region:
	var region: Region = Region.disc(species.size())
	for i: int in species.size():
		var spot: Vector2i = Vector2i(i, 0)
		region.wild_monsters.append(spot)
		region.add_placement(WildSpotPlacements.KIND, spot, WildSpot.NAMED + species[i])
	return region


static func _schedules(state: GameState) -> ScheduleFeature:
	return state.feature(ScheduleFeature.ID) as ScheduleFeature


## Every wild monster's day in `state`, in id order.
static func _days(state: GameState) -> Array[Array]:
	var days: Array[Array] = []
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in wild.monsters + wild.fainted:
		days.append(_schedules(state).day_of(monster))
	return days
