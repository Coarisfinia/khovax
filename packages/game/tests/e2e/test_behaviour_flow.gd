extends RefCounted
## Behaviour flow (#1199): wild monsters live by their species' behaviour traits. The day clock
## (#1201) follows the world's tick: a world starts at dawn, night falls at dusk, and a day later
## it's dawn again; every instance of the world shares it (#1215), one nobody is in and one loaded
## later too, and a save gives it back. Every wild monster gets a daily schedule from its traits and
## the instance's seed:
## a diurnal one sleeps one block at night, a nocturnal one one block by day, a cathemeral one in
## bouts by day and at night, a sleepless one never; each need takes its hours, and the rest it
## follows its pack, or wanders without one. What it's doing now follows the clock, and a fainted
## one does nothing. The schedules are the same for the same seed, differ for another, are in the
## state hash and come back the same from a save. The content's own species, the nocturnal
## Ombulumo and the diurnal Tikazzir, follow theirs in an instance the blueprints make.
##
## Wild monsters sleep by their schedules (#1202): asleep from the start when the instance starts in
## a sleep block, falling asleep as each block begins and waking as it ends, the sleepless never.
## Struck awake, one stays awake for the rest of its block and sleeps again in its next one. An
## instance nobody is in, which keeps the world's time without stepping, settles every hour it
## missed when it steps again (#1245), from a save made meanwhile too, so its monsters sleep as if
## it had stepped all along. Asleep, it strikes nobody, not even a player standing right next to
## it, whom it doesn't wake for; a strike or rage wakes it, and then it strikes again. A light
## sleeper (#1230), like the content's Tikazzir, does wake as soon as a player comes next to it,
## though not for one two tiles away.
##
## In its hunt hours (#1204), a predator stalks a grazer or weaker wild monster it sights, strikes
## it down to 1 HP and no further, and rests; it leaves a stronger one be and roams around its
## home; it gives up on prey it can't beat; outside its hunt hours it rests no more. A save in
## the middle of a hunt plays on the same, and the content's Tikazzir hunt in the basic instance.

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
## The hunt flow's species (#1204): a predator, a grazer as strong as it, a weaker and a stronger
## drinker, and a grazer it can't wear down. None sleeps, so none sleeps through a hunt.
const HUNT_TRAITS: Dictionary[String, Array] = {
	"hun": ["sleepless", "predator"],
	"gra": ["sleepless", "grazer"],
	"wea": ["sleepless", "drinker"],
	"str": ["sleepless", "drinker"],
	"tou": ["sleepless", "grazer"],
}
const HUNT_STRENGTHS: Dictionary[String, int] = {
	"hun": 10,
	"gra": 10,
	"wea": 5,
	"str": 20,
	"tou": 10,
}
const HUNT_HP: Dictionary[String, int] = {
	"hun": 50,
	"gra": 30,
	"wea": 30,
	"str": 30,
	"tou": 100_000,
}


func run(_tree: SceneTree) -> String:
	var steps: Array[Callable] = [
		_check_day_clock,
		_check_world_clock,
		_check_rhythms,
		_check_activity_follows_clock,
		_check_deterministic,
		_check_content_species,
		_check_sleep_follows_schedule,
		_check_woken_stays_awake,
		_check_sleep_catches_up,
		_check_sleeper_strikes_nobody,
		_check_hunt_won,
		_check_hunt_spares_stronger,
		_check_hunt_given_up,
		_check_hunt_saved,
		_check_content_hunters,
		_check_light_sleeper_wakes,
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
		return "a world didn't start at dawn"
	if DayClock.hour_of(DayClock.TICKS_PER_HOUR - 1) != DayClock.DAWN:
		return "the clock turned before an hour was up"
	if DayClock.hour_of(dusk) != DayClock.DUSK or DayClock.is_day_hour(DayClock.hour_of(dusk)):
		return "night didn't fall at dusk"
	if not DayClock.is_day_hour(DayClock.hour_of(dusk - 1)):
		return "night fell before dusk"
	if DayClock.hour_of(day) != DayClock.DAWN or DayClock.hour_of(day + dusk) != DayClock.DUSK:
		return "the next day didn't run like the first"
	return ""


## Every instance of a world tells the world's time (#1215): the one a player walks into, loaded
## late, the one they left, which no longer steps, and both after a save, which hashes the same.
func _check_world_clock() -> String:
	var world: World = World.new(BlueprintSource.new(), SEED, FlowSteps.FOREST)
	for _tick: int in DayClock.TICKS_PER_HOUR:
		world.step(FlowSteps.command(Command.NO_MOVE))
	for direction: int in FlowSteps.INTO_GLADE:
		world.step(FlowSteps.command(direction))
		for _tick: int in MovementFeature.MOVE_TICKS + 1:
			world.step(FlowSteps.command(Command.NO_MOVE))
	if world.instance_of(0) != FlowSteps.GLADE:
		return "the player didn't walk from the forest into the glade"
	for _tick: int in DayClock.TICKS_PER_HOUR:
		world.step(FlowSteps.command(Command.NO_MOVE))
	var problem: String = _clock_problem(world, "after walking into the glade")
	if not problem.is_empty():
		return problem
	var resumed: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	if not resumed.problem.is_empty() or resumed.state_hash() != world.state_hash():
		return "the world didn't come back from its save: %s" % resumed.problem
	return _clock_problem(resumed, "after a save")


## Why some instance of `world` doesn't tell the world's time `when`, or "".
static func _clock_problem(world: World, when: String) -> String:
	if world.sorted_names().size() < 2:
		return "%s, the world has only %s loaded" % [when, world.sorted_names()]
	for instance_name: String in world.sorted_names():
		var state: GameState = world.instances[instance_name]
		if (state.world_tick != world.tick
				or DayClock.hour_now(state) != DayClock.hour_of(world.tick)):
			return "%s, %s's clock is at %d, the world's at %d" % [
				when,
				instance_name,
				state.world_tick,
				world.tick,
			]
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
			state.world_tick = from_dawn * DayClock.TICKS_PER_HOUR
			if schedules.activity_of(state, monster) != day[hour]:
				return "monster %d didn't do at %d o'clock what its day says" % [monster, hour]
	var first: int = wild.monsters[0]
	var first_day: Array[int] = schedules.day_of(first)
	state.world_tick = DayClock.TICKS_PER_HOUR - 1
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
	wild.sleep(wild.monsters[0], true)
	var slept: GameState = _test_state(SEED, TEST_TRAITS)
	slept.load_data(DataReader.new(state.to_data()))
	if (slept.feature(WildMonsterFeature.ID) as WildMonsterFeature).asleep != wild.asleep:
		return "a save didn't give back which wild monsters sleep"
	if slept.state_hash() != state.state_hash() or slept.state_hash() == loaded.state_hash():
		return "who sleeps isn't in the state hash"
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
	if basic.feature(ScheduleFeature.ID) == null or basic.feature(SleepFeature.ID) == null:
		return "the basic instance's wild monsters have no schedules or don't sleep"
	var basic_wild: WildMonsterFeature = basic.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in basic_wild.monsters:
		if (basic.feature(ScheduleFeature.ID) as ScheduleFeature).day_of(monster).is_empty():
			return "the basic instance's wild monster %d has no day" % monster
	return ""


## Every test monster sleeps when its day says it sleeps, from the instance's start and on every
## hour of a whole day, stepped onto by a real tick; each rhythm but the sleepless sleeps at some
## hour.
func _check_sleep_follows_schedule() -> String:
	var state: GameState = _test_state(SEED, TEST_TRAITS)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var problem: String = _sleep_follows(state, "at the start")
	if not problem.is_empty():
		return problem
	var slept: Dictionary[String, bool] = {}
	for hour: int in range(1, DayClock.HOURS + 1):
		_step_onto(state, hour * DayClock.TICKS_PER_HOUR)
		problem = _sleep_follows(state, "%d hours after dawn" % hour)
		if not problem.is_empty():
			return problem
		for monster: int in wild.asleep:
			slept[wild.species_of(monster)] = true
	var sleepers: Array[String] = []
	sleepers.assign(slept.keys())
	sleepers.sort()
	if sleepers != ["cat", "diu", "noc"]:
		return "over a whole day, only %s slept" % [sleepers]
	return ""


## A monster struck awake as its sleep block begins stays awake for the rest of the block, and
## falls asleep again as its next block begins, a day later.
func _check_woken_stays_awake() -> String:
	var state: GameState = _test_state(SEED, TEST_TRAITS)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var diurnal: int = wild.monsters[TEST_TRAITS.keys().find("diu")]
	var day: Array[int] = _schedules(state).day_of(diurnal)
	var bedtime: int = DayClock.DUSK
	while day[bedtime] != Schedule.SLEEP:
		bedtime += 1
	var at_bedtime: int = (bedtime - DayClock.DAWN) * DayClock.TICKS_PER_HOUR
	_step_onto(state, at_bedtime)
	if not wild.asleep.has(diurnal):
		return "the diurnal monster didn't fall asleep at bedtime"
	wild.wound(state, diurnal, 1)
	if wild.asleep.has(diurnal):
		return "a strike didn't wake a sleeping wild monster"
	_step_onto(state, at_bedtime + DayClock.TICKS_PER_HOUR)
	if wild.asleep.has(diurnal):
		return "a wild monster struck awake fell asleep again within its sleep block"
	_step_onto(state, at_bedtime + DayClock.HOURS * DayClock.TICKS_PER_HOUR)
	if not wild.asleep.has(diurnal):
		return "a wild monster struck awake didn't sleep again the next night"
	return ""


## An instance that stood still while the world's time went on, as one nobody is in does (#1215),
## and was saved and loaded meanwhile, sleeps on its next step as one that stepped all along
## (#1245): after part of an hour, after a few hours and after more than a day.
func _check_sleep_catches_up() -> String:
	var stepped: GameState = _test_state(SEED, TEST_TRAITS)
	var half_hour: int = Fixed.div_floor(DayClock.TICKS_PER_HOUR, 2)
	for hours: int in [0, 1, 5, 13, 30]:
		var back: int = hours * DayClock.TICKS_PER_HOUR + half_hour
		while stepped.world_tick < back:
			Simulation.step(stepped, FlowSteps.command(Command.NO_MOVE))
		var returned: GameState = _returned_onto(back)
		if returned == null:
			return "a save of an instance standing still didn't hash the same"
		var wild: WildMonsterFeature = returned.feature(WildMonsterFeature.ID) as WildMonsterFeature
		if wild.asleep != (stepped.feature(WildMonsterFeature.ID) as WildMonsterFeature).asleep:
			return "back after %d hours, other wild monsters slept than after stepping" % hours
	return ""


## A test instance that stepped once, then stood still until the world's tick `back` - 1, was
## saved and loaded there, and stepped onto `back`; null when the loaded one hashed otherwise.
static func _returned_onto(back: int) -> GameState:
	var still: GameState = _test_state(SEED, TEST_TRAITS)
	Simulation.step(still, FlowSteps.command(Command.NO_MOVE))
	still.world_tick = back - 1
	var loaded: GameState = _test_state(SEED, TEST_TRAITS)
	loaded.load_data(DataReader.new(still.to_data()))
	loaded.world_tick = still.world_tick
	if loaded.state_hash() != still.state_hash():
		return null
	Simulation.step(loaded, FlowSteps.command(Command.NO_MOVE))
	return loaded


## In the blueprints' basic instance, a sleeping wild monster of a deep-sleeping species strikes
## nobody, not even the player standing next to it, who doesn't wake it either. Struck, it wakes and
## strikes the player; rage wakes one too.
func _check_sleeper_strikes_nobody() -> String:
	var state: GameState = FlowSteps.basic(SEED)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var stuck: Dictionary[Vector2i, bool] = RingableGround.unringable(state.region)
	# One that stands still awake too: not held, not hidden, on ground a ring could enclose, and
	# not a light sleeper, which the player would wake.
	var monster: int = 0
	for each: int in wild.monsters:
		var held: bool = wild.held.has(each) or (hiding != null and hiding.is_hidden(each))
		if (not held
				and not stuck.has(state.entity(each).tile)
				and not _schedules(state).has_trait(state, each, SpeciesBehaviour.LIGHT_SLEEPER)):
			monster = each
			break
	if monster == 0:
		return "the basic instance has no deep-sleeping wild monster standing free"
	var tile: Vector2i = state.entity(monster).tile
	if not _place_player(state, tile, 1):
		return "the player found no room next to wild monster %d" % monster
	wild.sleep(monster, true)
	if _strikes(state, monster) > 0:
		return "a sleeping wild monster struck the player next to it"
	if not wild.asleep.has(monster):
		return "a player next to a sleeping wild monster woke it"
	wild.wound(state, monster, 1)
	if wild.asleep.has(monster) or _strikes(state, monster) == 0:
		return "a wild monster struck awake didn't strike the player next to it"
	wild.sleep(monster, true)
	wild.enrage(state, monster, 0)
	if wild.asleep.has(monster):
		return "rage didn't wake a sleeping wild monster"
	return ""


## A sleeping light sleeper (#1230) sleeps on while a player stands two tiles away, and wakes on
## the tick the player stands next to it; the content's Tikazzir is one.
func _check_light_sleeper_wakes() -> String:
	var tikazzir: Species = SpeciesContent.cached().species["tikazzir"]
	if not tikazzir.behaviour.has(SpeciesBehaviour.LIGHT_SLEEPER):
		return "the content's Tikazzir isn't a light sleeper"
	var traits: Dictionary[String, Array] = TEST_TRAITS.duplicate(true)
	traits["diu"].append(SpeciesBehaviour.LIGHT_SLEEPER)
	var state: GameState = _test_state(SEED, traits)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var monster: int = wild.monsters[TEST_TRAITS.keys().find("diu")]
	var tile: Vector2i = state.entity(monster).tile
	var _player: Entity = state.add_entity(0, tile + Vector2i(0, 3))
	if not _place_player(state, tile, 2):
		return "the player found no room two tiles from the light sleeper"
	wild.sleep(monster, true)
	for _tick: int in MovementFeature.MOVE_TICKS:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if not wild.asleep.has(monster):
		return "a player two tiles from a sleeping light sleeper woke it"
	if not _place_player(state, tile, 1):
		return "the player found no room next to the light sleeper"
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if wild.asleep.has(monster):
		return "a player next to a sleeping light sleeper didn't wake it"
	return ""


## Puts the player of slot 0 on a free walkable tile `distance` tiles from `tile`; whether there
## was one.
static func _place_player(state: GameState, tile: Vector2i, distance: int) -> bool:
	for side: Vector2i in Hex.ring(distance, tile):
		if state.region.is_walkable(side) and _nobody_on(state, side):
			state.player(0).tile = side
			return true
	return false


## How many times the wild monster `monster` strikes over two of its strikes' time, standing still.
static func _strikes(state: GameState, monster: int) -> int:
	var strikes: int = 0
	for _tick: int in WildAttackFeature.STRIKE_TICKS * 2:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		for event: RefCounted in state.events:
			var struck: WildMonsterStruck = event as WildMonsterStruck
			if struck != null and struck.monster_id == monster:
				strikes += 1
	return strikes


## Whether nothing stands on `tile` in `state`.
static func _nobody_on(state: GameState, tile: Vector2i) -> bool:
	for entity: Entity in state.entities:
		if entity.tile == tile:
			return false
	return true


## Steps `state` by a real tick onto the world's tick `tick`, whatever tick it was on.
static func _step_onto(state: GameState, tick: int) -> void:
	state.world_tick = tick - 1
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))


## Why the wild monsters of `state` don't sleep as their days say `when`, or "".
static func _sleep_follows(state: GameState, when: String) -> String:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in wild.monsters:
		var sleeping: bool = _schedules(state).activity_of(state, monster) == Schedule.SLEEP
		if wild.asleep.has(monster) != sleeping:
			return "%s %s asleep %s, against its day" % [
				wild.species_of(monster),
				"was" if wild.asleep.has(monster) else "wasn't",
				when,
			]
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
		SleepFeature.new(),
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


## The predator stalks the grazer it sights, strikes it for its strength, never below 1 HP, and
## rests once it's beaten; past its hunt hours it rests no more.
func _check_hunt_won() -> String:
	var state: GameState = _hunt_state({ "hun": Vector2i(-2, 0), "gra": Vector2i(1, 0) })
	var hunter: int = _monster_of(state, "hun")
	var target: int = _monster_of(state, "gra")
	var hunts: HuntFeature = state.feature(HuntFeature.ID) as HuntFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	_to_hunt_hours(state, hunter)
	var damage: Array[int] = []
	for _tick: int in 20 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		damage.append_array(_strikes_on(state, hunter, target))
		if hunts.rested.has(hunter):
			break
	var problem: String = _damage_problem(damage)
	if not problem.is_empty():
		return problem
	if not hunts.rested.has(hunter) or health.hp_of(state, target) != 1:
		return "the hunt didn't end with the prey down to 1 HP: %d" % health.hp_of(state, target)
	if Hex.distance(state.entity(hunter).tile, state.entity(target).tile) != 1:
		return "the predator struck its prey from afar"
	for _tick: int in 3 * WildAttackFeature.STRIKE_TICKS:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		for event: RefCounted in state.events:
			if event is WildMonsterStruck:
				return "a resting predator struck again"
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild.is_fainted(target):
		return "the hunt felled its prey"
	_out_of_hunt_hours(state, hunter)
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if hunts.rested.has(hunter):
		return "the predator still rested past its hunt hours"
	return ""


## A stronger wild monster that's no grazer isn't prey: the predator leaves it be and roams
## around its home, never further than ROAM_RADIUS.
func _check_hunt_spares_stronger() -> String:
	var state: GameState = _hunt_state({ "hun": Vector2i(-2, 0), "str": Vector2i(-2, 2) })
	var hunter: int = _monster_of(state, "hun")
	var home: Vector2i = state.entity(hunter).tile
	_to_hunt_hours(state, hunter)
	var roamed: bool = false
	for _tick: int in 20 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		if state.events.any(func(event: RefCounted) -> bool: return event is WildMonsterStruck):
			return "the predator struck a stronger wild monster"
		var tile: Vector2i = state.entity(hunter).tile
		if Hex.distance(tile, home) > HuntFeature.ROAM_RADIUS:
			return "the predator roamed %d tiles from home" % Hex.distance(tile, home)
		roamed = roamed or tile != home
	if not roamed:
		return "the predator didn't roam in its hunt hours"
	return ""


## Prey it can't wear down, the predator gives up on after GIVE_UP_TICKS, and rests; a weaker
## wild monster is prey too.
func _check_hunt_given_up() -> String:
	var state: GameState = _hunt_state({ "hun": Vector2i(-1, 0), "tou": Vector2i(0, 0) })
	var hunter: int = _monster_of(state, "hun")
	var hunts: HuntFeature = state.feature(HuntFeature.ID) as HuntFeature
	_to_hunt_hours(state, hunter)
	for _tick: int in HuntFeature.GIVE_UP_TICKS - Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if hunts.rested.has(hunter) or hunts.prey.get(hunter, 0) != _monster_of(state, "tou"):
		return "the predator gave up too soon"
	for _tick: int in 2 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if not hunts.rested.has(hunter):
		return "the predator never gave up on prey it can't beat"
	var weaker: GameState = _hunt_state({ "hun": Vector2i(-1, 0), "wea": Vector2i(1, 0) })
	var weak_hunter: int = _monster_of(weaker, "hun")
	var prey: int = _monster_of(weaker, "wea")
	var weak_hunts: HuntFeature = weaker.feature(HuntFeature.ID) as HuntFeature
	_to_hunt_hours(weaker, weak_hunter)
	# Hunted to the end: its prey beaten, it rests (a hunt ends within a few strikes).
	var strikes: int = 0
	for _tick: int in 20 * Simulation.TICKS_PER_SECOND:
		Simulation.step(weaker, FlowSteps.command(Command.NO_MOVE))
		strikes += _strikes_on(weaker, weak_hunter, prey).size()
		if weak_hunts.rested.has(weak_hunter):
			break
	var health: HealthFeature = weaker.feature(HealthFeature.ID) as HealthFeature
	if strikes == 0 or health.hp_of(weaker, prey) != 1 or not weak_hunts.rested.has(weak_hunter):
		return "the predator didn't hunt a weaker wild monster down"
	return ""


## A save taken in the middle of a hunt plays on the same as the hunt it was taken from.
func _check_hunt_saved() -> String:
	var spots: Dictionary[String, Vector2i] = { "hun": Vector2i(-2, 0), "gra": Vector2i(2, 0) }
	var state: GameState = _hunt_state(spots)
	_to_hunt_hours(state, _monster_of(state, "hun"))
	for _tick: int in 3 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	var hunts: HuntFeature = state.feature(HuntFeature.ID) as HuntFeature
	if hunts.prey.is_empty():
		return "no hunt was going on to save"
	var loaded: GameState = _hunt_state(spots)
	loaded.load_data(DataReader.new(state.to_data()))
	# The world's time isn't the instance's to save: the World hands it to a loaded one (#1215).
	loaded.world_tick = state.world_tick
	if loaded.state_hash() != state.state_hash():
		return "a save in the middle of a hunt didn't load the same"
	for _tick: int in 5 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		Simulation.step(loaded, FlowSteps.command(Command.NO_MOVE))
	if loaded.state_hash() != state.state_hash():
		return "a loaded hunt played on otherwise"
	return ""


## The content's predators, the Tikazzir, are hunters at home in the basic instance; its grazer
## Ombulumo isn't. The basic instance rolls its species, so the seeds are tried until one places
## a Tikazzir.
func _check_content_hunters() -> String:
	for seed_value: int in 20:
		var basic: GameState = FlowSteps.basic(seed_value)
		var hunts: HuntFeature = basic.feature(HuntFeature.ID) as HuntFeature
		if hunts == null:
			return "the basic instance has no hunts"
		var wild: WildMonsterFeature = basic.feature(WildMonsterFeature.ID) as WildMonsterFeature
		for monster: int in wild.monsters:
			if hunts.homes.has(monster) != (wild.species_of(monster) == "tikazzir"):
				return "%s's monster %d isn't a hunter by its traits" % [
					wild.species_of(monster),
					monster,
				]
		if not hunts.homes.is_empty():
			return ""
	return "no seed placed a Tikazzir to hunt in the basic instance"


## Why the hunter's strikes on the grazer, `damage`, aren't its strength each, but the last no
## more than leaves the prey its last HP; or "".
static func _damage_problem(damage: Array[int]) -> String:
	if damage.is_empty():
		return "the predator never struck the grazer it sighted"
	var strength: int = HUNT_STRENGTHS["hun"]
	var dealt: int = 0
	for i: int in damage.size():
		dealt += damage[i]
		if damage[i] > strength or (damage[i] < strength and i < damage.size() - 1):
			return "the hunter struck for %s, not its strength" % [damage]
	if dealt != HUNT_HP["gra"] - 1:
		return "the hunt's strikes didn't add up to all but the prey's last HP"
	return ""


## The damage of each strike `hunter` dealt `target` this tick.
static func _strikes_on(state: GameState, hunter: int, target: int) -> Array[int]:
	var damage: Array[int] = []
	for event: RefCounted in state.events:
		var struck: WildMonsterStruck = event as WildMonsterStruck
		if struck != null and struck.monster_id == hunter and struck.target_id == target:
			damage.append(struck.damage)
	return damage


## A disc with a wild monster of each hunt flow species in `spots` where it says, with the hunts.
static func _hunt_state(spots: Dictionary[String, Vector2i]) -> GameState:
	var region: Region = Region.disc(8)
	for species: String in spots:
		region.wild_monsters.append(spots[species])
		region.add_placement(WildSpotPlacements.KIND, spots[species], WildSpot.NAMED + species)
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(HUNT_HP),
		WildMonsterFeature.new([], [], HUNT_STRENGTHS),
		ScheduleFeature.new(HUNT_TRAITS),
		HuntFeature.new(),
	]
	return GameState.new(region, SEED, ordered)


## The entity id of `state`'s wild monster of `species`.
static func _monster_of(state: GameState, species: String) -> int:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in wild.monsters + wild.fainted:
		if wild.species_of(monster) == species:
			return monster
	return 0


## Sets `state`'s clock to the start of the first of `monster`'s hunt hours.
static func _to_hunt_hours(state: GameState, monster: int) -> void:
	_to_hour_doing(state, monster, Schedule.HUNT, true)


## Sets `state`'s clock to the start of the first hour `monster` doesn't hunt.
static func _out_of_hunt_hours(state: GameState, monster: int) -> void:
	_to_hour_doing(state, monster, Schedule.HUNT, false)


## Sets `state`'s clock to the start of the first hour from dawn in which `monster` is (or, not
## `doing`, isn't) busy with `activity`, keeping the day it's in.
static func _to_hour_doing(state: GameState, monster: int, activity: int, doing: bool) -> void:
	var day: Array[int] = _schedules(state).day_of(monster)
	var day_start: int = Fixed.div_floor(state.world_tick, DayClock.HOURS * DayClock.TICKS_PER_HOUR)
	for from_dawn: int in DayClock.HOURS:
		if (day[(DayClock.DAWN + from_dawn) % DayClock.HOURS] == activity) == doing:
			var hours: int = day_start * DayClock.HOURS + from_dawn
			state.world_tick = hours * DayClock.TICKS_PER_HOUR
			return
