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
## Hunted prey that's awake flees its hunter at its pace (#1239), a step at a time away from it and
## never off ground a ring could enclose it on, so it's cornered where the ground ends; sighted at
## the edge of its hunter's sight, it gets out of it, and the hunter roams on. Asleep, it stays put
## until a strike wakes it, and enraged it stands its ground. A hunter walks round a wall between
## it and its prey (#1259), a tile a step and never off ground a ring could enclose it on, where a
## greedy step would stall behind it; fleeing prey runs the way that leads furthest from its hunter,
## not into a dead end.
##
## Pack monsters band together (#1205): by species, or by a similar typing for `pack_type` ones,
## never more than a pack can hold; members live by their leader's day and, in the hours they
## follow their pack, walk back to their leader. A dominated or fainted leader hands the pack to its
## next member, a pack down to one is gone, and a save plays on the same. The content's Vynakiir
## band in Ivenwhal Wudhen.
##
## In its grazing hours a grazer walks to the nearest grass and eats there, and in its drinking
## hours a drinker finds its way round a rock wall to the nearest water and drinks (#1203).

## A test species of each sleep rhythm, with needs and bands that cover every activity.
const TEST_TRAITS: Dictionary[String, Array] = {
	"diu": ["diurnal", "grazer", "drinker"],
	"noc": ["nocturnal", "predator", "pack_species"],
	"cat": ["cathemeral", "grazer", "pack_type"],
	"sle": ["sleepless", "drinker", "predator"],
}
const SEED: int = 42
## How far the hunt flow's wall of rock (#1259) runs each way from the middle of its disc.
const WALL_HALF: int = 1
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
## The pack flow's species (#1205): wolves banding by species; a diurnal and a nocturnal one of a
## Lesser type and its Greater, which band by type; one banding by type of another family; and one
## that doesn't band.
const PACK_TRAITS: Dictionary[String, Array] = {
	"wol": ["sleepless", "grazer", "pack_species"],
	"arc": ["diurnal", "grazer", "pack_type"],
	"man": ["nocturnal", "drinker", "pack_type"],
	"sha": ["sleepless", "grazer", "pack_type"],
	"lon": ["sleepless", "grazer"],
}
const PACK_TYPES: Dictionary[String, Array] = {
	"wol": ["mana"],
	"arc": ["arcane"],
	"man": ["mana"],
	"sha": ["shadow"],
	"lon": ["mana"],
}
## Where each of the pack flow's wild monsters stands, in id order: five wolves close together,
## the fifth furthest, and the others apart from them.
const PACK_SPOTS: Dictionary[Vector2i, String] = {
	Vector2i(-5, 0): "wol",
	Vector2i(-5, 1): "wol",
	Vector2i(-4, 0): "wol",
	Vector2i(-3, 0): "wol",
	Vector2i(-1, 0): "wol",
	Vector2i(3, 0): "arc",
	Vector2i(5, 0): "man",
	Vector2i(3, 2): "sha",
	Vector2i(4, -2): "lon",
}
## A test grazer and drinker (#1203), and what each does in its hours of need.
const FORAGERS: Dictionary[String, Array] = {
	"gra": ["diurnal", "grazer"],
	"dri": ["diurnal", "drinker"],
}
const FORAGING: Dictionary[String, int] = { "gra": Schedule.GRAZE, "dri": Schedule.DRINK }
## The foraging region's grass, the nearer patch to the grazer first, its pond, and the rock
## wall's row between the drinker and the pond: all well inside its sand, where a ring could enclose
## a monster.
const FORAGE_GRASS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(4, -2)]
const FORAGE_WATER: Vector2i = Vector2i(0, -4)
const FORAGE_WALL_ROW: int = -2
## How long the flow lets a forager walk: enough steps to go round the wall, within one hour.
const FORAGE_TICKS: int = 12 * WildMonsterFeature.STEP_TICKS


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
		_check_prey_escapes,
		_check_prey_asleep_or_enraged,
		_check_hunt_spares_stronger,
		_check_hunt_given_up,
		_check_hunt_saved,
		_check_content_hunters,
		_check_hunt_round_wall,
		_check_flight_shuns_dead_end,
		_check_light_sleeper_wakes,
		_check_packs_band,
		_check_pack_follows,
		_check_pack_leader_lost,
		_check_pack_saved,
		_check_content_packs,
		_check_grazing_and_drinking,
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
	for feature_id: String in [ScheduleFeature.ID, SleepFeature.ID, ForagingFeature.ID]:
		if basic.feature(feature_id) == null:
			return "the basic instance's wild monsters lack the feature %s" % feature_id
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


## Ground is grass and water drinkable, sand neither (#1203). A grazer in its grazing hour walks
## to the nearer of two patches of grass, and a drinker in its drinking hour round the rock wall to
## the pond, each one tile at a time and only over ground a ring could enclose it on; then each
## stays there, eating or drinking, for the rest of the hour. In an hour of wandering, neither goes
## anywhere, a grazer with no grass about stays where it is, and one whose nearer grass is walled
## in walks to the further grass it can reach (#1291).
func _check_grazing_and_drinking() -> String:
	if not TileKinds.is_grazable(Region.GROUND) or not TileKinds.is_drinkable(Region.WATER):
		return "ground isn't grass or water isn't drinkable"
	if TileKinds.is_grazable("sand") or TileKinds.is_drinkable("sand"):
		return "sand is grass or drinkable"
	for species: String in FORAGERS:
		var state: GameState = _forage_state(true)
		var monster: int = _forager(state, species)
		var activity: int = FORAGING[species]
		var walked: Array[Vector2i] = _forage_at(state, monster, activity, FORAGE_TICKS)
		var problem: String = _walk_problem(state, walked, activity)
		if not problem.is_empty():
			return "%s %s" % [species, problem]
		if activity == Schedule.GRAZE and walked[-1] != FORAGE_GRASS[0]:
			return "the grazer went to %s, not the nearest grass" % walked[-1]
		if activity == Schedule.DRINK and walked.size() - 1 <= Hex.distance(walked[0], walked[-1]):
			return "the drinker went straight through the rock wall: %s" % [walked]
		var rest: int = DayClock.TICKS_PER_HOUR - state.world_tick % DayClock.TICKS_PER_HOUR - 1
		if _forage_at(state, monster, Schedule.NONE, rest).size() != 1:
			return "%s didn't stay to eat or drink for the rest of the hour" % species
		if _forage_at(state, monster, Schedule.WANDER, FORAGE_TICKS).size() != 1:
			return "%s walked off in an hour without grazing or drinking" % species
	var bare: GameState = _forage_state(false)
	var grazer: int = _forager(bare, "gra")
	if _forage_at(bare, grazer, Schedule.GRAZE, FORAGE_TICKS).size() != 1:
		return "a grazer with no grass about walked off"
	return _check_grass_behind_wall()


## A grazer picks its grass by the way it walks, not as the crow flies (#1291): with the nearer
## patch walled in by rock, it walks to the further one instead of stalling at the wall.
static func _check_grass_behind_wall() -> String:
	var state: GameState = _forage_state(true)
	for direction: Vector2i in Hex.DIRECTIONS:
		var _walled: bool = state.change_tile(FORAGE_GRASS[0] + direction, Region.BLOCKED)
	var grazer: int = _forager(state, "gra")
	var walked: Array[Vector2i] = _forage_at(state, grazer, Schedule.GRAZE, FORAGE_TICKS)
	var problem: String = _walk_problem(state, walked, Schedule.GRAZE)
	if not problem.is_empty():
		return "with the nearer grass walled in, the grazer %s" % problem
	if walked[-1] != FORAGE_GRASS[1]:
		return "with the nearer grass walled in, the grazer went to %s" % walked[-1]
	return ""


## Why `walked`, the tiles a monster doing `activity` stood on one after the other, isn't a walk to
## where it feeds, a tile at a time over ground a ring could enclose it on, or "".
static func _walk_problem(state: GameState, walked: Array[Vector2i], activity: int) -> String:
	if walked.size() < 2 or not ForageWay.feeds_at(state.region, walked[-1], activity):
		return "didn't walk to its food or water: %s" % [walked]
	var stuck: Dictionary[Vector2i, bool] = RingableGround.unringable(state.region)
	for i: int in range(1, walked.size()):
		if Hex.distance(walked[i - 1], walked[i]) != 1 or stuck.has(walked[i]):
			return "didn't walk a tile at a time over ringable ground: %s" % [walked]
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
	var ordered: Array[Feature] = _wild_features(health, traits)
	ordered.append(SleepFeature.new())
	return GameState.new(_region(species), seed_value, ordered)


## The features a test instance's wild monsters live by, up to their schedules made from
## `traits`, each species with the HP in `health` and the strength in `strengths`; each flow adds
## the behaviours it checks after them.
static func _wild_features(
	health: Dictionary[String, int],
	traits: Dictionary[String, Array],
	strengths: Dictionary[String, int] = {},
) -> Array[Feature]:
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(health),
		WildMonsterFeature.new([], [], strengths),
		ScheduleFeature.new(traits),
	]
	return ordered


## A sand disc with a grazer and a drinker on it, its grass (`grass`) to the east and its pond to
## the north behind a wall of rock, with the foraging feature after the schedules.
static func _forage_state(grass: bool) -> GameState:
	var region: Region = Region.disc(6)
	for tile: Vector2i in region.sorted_tiles():
		region.terrain[tile] = "sand"
	if grass:
		for patch: Vector2i in FORAGE_GRASS:
			region.terrain[patch] = Region.GROUND
	region.terrain[FORAGE_WATER] = Region.WATER
	for q: int in range(-2, 3):
		region.terrain[Vector2i(q, FORAGE_WALL_ROW)] = Region.BLOCKED
	var spots: Dictionary[String, Vector2i] = { "gra": Vector2i(-3, 2), "dri": Vector2i(0, 3) }
	var health: Dictionary[String, int] = {}
	for species: String in spots:
		region.wild_monsters.append(spots[species])
		region.add_placement(WildSpotPlacements.KIND, spots[species], WildSpot.NAMED + species)
		health[species] = 10
	var ordered: Array[Feature] = _wild_features(health, FORAGERS)
	ordered.append(SleepFeature.new())
	ordered.append(ForagingFeature.new())
	return GameState.new(region, SEED, ordered)


## The entity id of the wild monster of `species` in `state`.
static func _forager(state: GameState, species: String) -> int:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in wild.monsters:
		if wild.species_of(monster) == species:
			return monster
	return -1


## Sets the clock to the start of the first hour `monster` spends on `activity` (or leaves it, for
## Schedule.NONE), lets `ticks` pass, and gives the tiles it stood on one after the other, the first
## included.
static func _forage_at(
	state: GameState,
	monster: int,
	activity: int,
	ticks: int,
) -> Array[Vector2i]:
	if activity != Schedule.NONE:
		var hour: int = _schedules(state).day_of(monster).find(activity)
		var from_dawn: int = (hour - DayClock.DAWN + DayClock.HOURS) % DayClock.HOURS
		state.world_tick = from_dawn * DayClock.TICKS_PER_HOUR
	var walked: Array[Vector2i] = [state.entity(monster).tile]
	for _tick: int in ticks:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		if state.entity(monster).tile != walked[-1]:
			walked.append(state.entity(monster).tile)
	return walked


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
	var fled: String = _hunted_down(state, hunter, target, damage)
	if not fled.is_empty():
		return fled
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


## Plays the hunt of `hunter` on `target` for up to 20 s, until the hunter rests, adding the damage
## of each strike on it to `damage`; says why the prey didn't flee by the rules (#1239), or "".
static func _hunted_down(state: GameState, hunter: int, target: int, damage: Array[int]) -> String:
	var hunts: HuntFeature = state.feature(HuntFeature.ID) as HuntFeature
	var start: Vector2i = state.entity(target).tile
	for _tick: int in 20 * Simulation.TICKS_PER_SECOND:
		var hunter_was: Vector2i = state.entity(hunter).tile
		var prey_was: Vector2i = state.entity(target).tile
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		var fled: String = _flight_problem(state, target, prey_was, hunter_was)
		if not fled.is_empty():
			return fled
		damage.append_array(_strikes_on(state, hunter, target))
		if hunts.rested.has(hunter):
			break
	if state.entity(target).tile == start:
		return "the hunted grazer never fled"
	return ""


## Why the hunted wild monster `target`, on `was` before the tick and hunted from `hunter_was`,
## didn't flee by the rules (#1239): it stepped no nearer its hunter, a tile at most, and never onto
## ground no ring could enclose it on; or "".
static func _flight_problem(
	state: GameState,
	target: int,
	was: Vector2i,
	hunter_was: Vector2i,
) -> String:
	var tile: Vector2i = state.entity(target).tile
	if tile == was:
		return ""
	if Hex.distance(
		tile,
		was,
	) != 1 or Hex.distance(tile, hunter_was) <= Hex.distance(was, hunter_was):
		return "the hunted grazer stepped from %s to %s, not away from %s" % [was, tile, hunter_was]
	if RingableGround.unringable(state.region).has(tile):
		return "the hunted grazer fled onto ground no ring could enclose it on: %s" % tile
	return ""


## Prey sighted at the edge of its hunter's sight flees out of it on its first step: the hunt is
## lost, and the hunter roams on without resting.
func _check_prey_escapes() -> String:
	var state: GameState = _hunt_state({ "hun": Vector2i(-2, 0), "gra": Vector2i(2, 0) })
	var hunter: int = _monster_of(state, "hun")
	var target: int = _monster_of(state, "gra")
	var hunts: HuntFeature = state.feature(HuntFeature.ID) as HuntFeature
	_to_hunt_hours(state, hunter)
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if hunts.prey.get(hunter, 0) != target:
		return "the predator didn't sight the grazer at the edge of its sight"
	for _tick: int in WildMonsterFeature.STEP_TICKS:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		if hunts.prey.is_empty():
			break
	var gap: int = Hex.distance(state.entity(hunter).tile, state.entity(target).tile)
	if not hunts.prey.is_empty() or hunts.rested.has(hunter) or gap <= HuntFeature.SIGHT:
		return "the grazer didn't flee out of sight, or its hunter didn't roam on: %d away" % gap
	return ""


## A sleeping grazer the predator stalks stays put until its strike wakes it, and then flees; an
## enraged one stands its ground.
func _check_prey_asleep_or_enraged() -> String:
	for enraged: bool in [false, true]:
		var state: GameState = _hunt_state({ "hun": Vector2i(-2, 0), "gra": Vector2i(1, 0) })
		var hunter: int = _monster_of(state, "hun")
		var target: int = _monster_of(state, "gra")
		var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
		if enraged:
			wild.enrage(state, target, 0)
		else:
			wild.sleep(target, true)
		_to_hunt_hours(state, hunter)
		var start: Vector2i = state.entity(target).tile
		var struck: int = -1
		for tick: int in 10 * Simulation.TICKS_PER_SECOND:
			Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
			if struck < 0 and not _strikes_on(state, hunter, target).is_empty():
				struck = tick
			if struck < 0 and state.entity(target).tile != start:
				return "the grazer left its tile before a strike, though asleep or enraged"
		if struck < 0:
			return "the predator never struck the grazer that didn't flee"
		if (state.entity(target).tile == start) != enraged:
			return "struck awake, the grazer didn't flee, or enraged, it fled"
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
	var spots: Dictionary[String, Vector2i] = { "hun": Vector2i(-2, 0), "gra": Vector2i(1, 0) }
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


## A predator walks round a wall of rock between it and its sleeping prey (#1259), a tile a step
## and never onto ground no ring could enclose it on, and strikes it; a greedy step toward it would
## stall behind the wall.
func _check_hunt_round_wall() -> String:
	var state: GameState = _hunt_state({ "hun": Vector2i(-2, 0), "gra": Vector2i(2, 0) })
	var hunter: int = _monster_of(state, "hun")
	var target: int = _monster_of(state, "gra")
	for r: int in range(-WALL_HALF, WALL_HALF + 1):
		if not state.change_tile(Vector2i(0, r), "rock"):
			return "the wall's tile %s didn't turn to rock" % Vector2i(0, r)
	(state.feature(WildMonsterFeature.ID) as WildMonsterFeature).sleep(target, true)
	_to_hunt_hours(state, hunter)
	var stuck: Dictionary[Vector2i, bool] = RingableGround.unringable(state.region)
	var round_end: bool = false
	for _tick: int in HuntFeature.GIVE_UP_TICKS:
		var was: Vector2i = state.entity(hunter).tile
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		var tile: Vector2i = state.entity(hunter).tile
		if Hex.distance(tile, was) > 1 or stuck.has(tile) or not state.region.is_walkable(tile):
			return "the hunter went from %s to %s round the wall" % [was, tile]
		round_end = round_end or absi(tile.y) > WALL_HALF
		if not _strikes_on(state, hunter, target).is_empty():
			if not round_end:
				return "the hunter struck its prey without walking round the wall"
			return ""
	return "the hunter never got round the wall to its prey: it stands on %s" % (
		state.entity(hunter).tile
	)


## Hunted prey with two ways away from its hunter takes the one that leads furthest (#1259): not
## the first in direction order, which runs into a dead end of rock a step on.
func _check_flight_shuns_dead_end() -> String:
	var state: GameState = _hunt_state({ "hun": Vector2i(-1, 0), "gra": Vector2i(1, 0) })
	var hunter: int = _monster_of(state, "hun")
	var target: int = _monster_of(state, "gra")
	var prey_tile: Vector2i = state.entity(target).tile
	# The ways one step further from the hunter, in direction order; rock walls the first in, one
	# step on, and blocks the rest but the last, so only the last runs on.
	var ways: Array[Vector2i] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		var tile: Vector2i = prey_tile + direction
		if Hex.distance(tile, Vector2i(-1, 0)) > Hex.distance(prey_tile, Vector2i(-1, 0)):
			ways.append(tile)
	for way: Vector2i in ways.slice(1, ways.size() - 1):
		var _walled: bool = state.change_tile(way, "rock")
	for direction: Vector2i in Hex.DIRECTIONS:
		var beyond: Vector2i = ways[0] + direction
		if not ways.has(beyond) and Hex.distance(beyond, Vector2i(-1, 0)) > 2:
			var _rock: bool = state.change_tile(beyond, "rock")
	_to_hunt_hours(state, hunter)
	for _tick: int in 2 * WildMonsterFeature.STEP_TICKS:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		if state.entity(target).tile != prey_tile:
			break
	if state.entity(target).tile != ways[ways.size() - 1]:
		return "the hunted grazer fled from %s to %s, not the open way %s" % [
			prey_tile,
			state.entity(target).tile,
			ways[ways.size() - 1],
		]
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
	var ordered: Array[Feature] = _wild_features(HUNT_HP, HUNT_TRAITS, HUNT_STRENGTHS)
	ordered.append(HuntFeature.new())
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


## Wild monsters band into packs as their traits say (#1205): five of a `pack_species` species
## close together make a pack of PACK_SIZE and leave the last alone; two `pack_type` ones of a
## Lesser type and its Greater band; one of another family, and one that doesn't band, stay alone.
## Every member lives by its leader's day, the nocturnal member of a diurnal leader too.
func _check_packs_band() -> String:
	var state: GameState = _pack_state(true)
	var packs: PackFeature = state.feature(PackFeature.ID) as PackFeature
	var wolves: Array[int] = _monsters_of(state, "wol")
	var expected: Dictionary[int, int] = {
		wolves[1]: wolves[0],
		wolves[2]: wolves[0],
		wolves[3]: wolves[0],
		_monsters_of(state, "man")[0]: _monsters_of(state, "arc")[0],
	}
	if packs.leaders != expected:
		return "the packs banded as %s, not %s" % [packs.leaders, expected]
	for member: int in packs.leaders:
		if _schedules(state).day_of(member) != _schedules(state).day_of(packs.leaders[member]):
			return "pack member %d doesn't live by its leader's day" % member
	var alone: GameState = _pack_state(false)
	var follower: int = _monsters_of(state, "man")[0]
	if _schedules(alone).day_of(follower) == _schedules(state).day_of(follower):
		return "the nocturnal member's day didn't change for its diurnal leader's"
	return ""


## In the hours it follows its pack, a member far from its leader walks back to it and stays near,
## while its leader stays where it is.
func _check_pack_follows() -> String:
	var state: GameState = _pack_state(true)
	var wolves: Array[int] = _monsters_of(state, "wol")
	var leader_tile: Vector2i = state.entity(wolves[0]).tile
	_to_hour_doing(state, wolves[0], Schedule.FOLLOW_PACK, true)
	state.entity(wolves[1]).tile = leader_tile + Vector2i(0, 5)
	for _tick: int in 8 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if state.entity(wolves[0]).tile != leader_tile:
		return "the leader walked off after its pack"
	var gap: int = Hex.distance(state.entity(wolves[1]).tile, leader_tile)
	if gap > PackFeature.KEEP_NEAR:
		return "a pack member stayed %d tiles from its leader" % gap
	return ""


## A dominated leader hands its pack to its member with the lowest id, whose own day the rest live
## by; a leader that faints does the same; a pack down to one is gone, and its last monster lives
## by its own day again, and so does a member that left.
func _check_pack_leader_lost() -> String:
	var state: GameState = _pack_state(true)
	var alone: GameState = _pack_state(false)
	var packs: PackFeature = state.feature(PackFeature.ID) as PackFeature
	var wolves: Array[int] = _monsters_of(state, "wol")
	# The type pack stands apart from the wolves' until its own leader is dominated below.
	var follower: int = _monsters_of(state, "man")[0]
	var type_leader: int = _monsters_of(state, "arc")[0]
	state.remove_entity(wolves[0])
	var expected: Dictionary[int, int] = {
		wolves[2]: wolves[1],
		wolves[3]: wolves[1],
		follower: type_leader,
	}
	var problem: String = _pack_problem(state, alone, expected, wolves[1], "dominated")
	if not problem.is_empty():
		return problem
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	wild.wound(state, wolves[1], 1000, true)
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	expected = { wolves[3]: wolves[2], follower: type_leader }
	problem = _pack_problem(state, alone, expected, wolves[2], "fainted")
	if not problem.is_empty():
		return problem
	if _schedules(state).day_of(wolves[1]) != _schedules(alone).day_of(wolves[1]):
		return "the fainted leader didn't get its own day back"
	state.remove_entity(type_leader)
	expected = { wolves[3]: wolves[2] }
	problem = _pack_problem(state, alone, expected, wolves[2], "down to one")
	if not problem.is_empty():
		return problem
	var last: int = follower
	if _schedules(state).day_of(last) != _schedules(alone).day_of(last) or packs.leaders.has(last):
		return "the last monster of a pack didn't live by its own day again"
	return ""


## Why `state`'s packs aren't `expected`, each member on its leader's day, the new leader `leader`
## on its own as in `alone`, once a leader was `how`; or "".
static func _pack_problem(
	state: GameState,
	alone: GameState,
	expected: Dictionary[int, int],
	leader: int,
	how: String,
) -> String:
	var packs: PackFeature = state.feature(PackFeature.ID) as PackFeature
	if packs.leaders != expected:
		return "once the leader %s, the packs were %s, not %s" % [how, packs.leaders, expected]
	if _schedules(state).day_of(leader) != _schedules(alone).day_of(leader):
		return "once the leader %s, the new leader didn't keep its own day" % how
	for member: int in expected:
		if _schedules(state).day_of(member) != _schedules(state).day_of(expected[member]):
			return "once the leader %s, member %d didn't live by its leader's day" % [how, member]
	return ""


## A save taken while a pack gathers, and after its leader was dominated, loads the same and plays
## on the same.
func _check_pack_saved() -> String:
	var state: GameState = _pack_state(true)
	var wolves: Array[int] = _monsters_of(state, "wol")
	_to_hour_doing(state, wolves[0], Schedule.FOLLOW_PACK, true)
	state.entity(wolves[2]).tile = state.entity(wolves[0]).tile + Vector2i(0, 5)
	state.remove_entity(wolves[0])
	for _tick: int in 2 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	var loaded: GameState = _pack_state(true)
	loaded.load_data(DataReader.new(state.to_data()))
	# The world's time comes back with the world's save (#1215), not the instance's.
	loaded.world_tick = state.world_tick
	if loaded.state_hash() != state.state_hash():
		return "a save of a pack didn't load the same"
	for _tick: int in 5 * Simulation.TICKS_PER_SECOND:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		Simulation.step(loaded, FlowSteps.command(Command.NO_MOVE))
	if loaded.state_hash() != state.state_hash():
		return "a loaded pack played on otherwise"
	return ""


## The content's Vynakiir, wolves that hunt in packs, band into one in Ivenwhal Wudhen, their home,
## and so do their pups, the Vynnimu (#1220), each with its own kind: both are `pack_species`.
func _check_content_packs() -> String:
	var state: GameState = InstanceBlueprints.create("ivenwhal_wudhen", SEED, 1)
	var packs: PackFeature = state.feature(PackFeature.ID) as PackFeature
	if packs == null or packs.leaders.is_empty():
		return "the Vynakiir of Ivenwhal Wudhen don't band into a pack"
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var banded: Dictionary[String, bool] = {}
	for member: int in packs.leaders:
		var leader: int = packs.leaders[member]
		var species: String = wild.species_of(member)
		if not species in ["vynakiir", "vynnimu"] or wild.species_of(leader) != species:
			return "a pack in Ivenwhal Wudhen isn't of Vynakiir or of Vynnimu alone"
		banded[species] = true
	for species: String in ["vynakiir", "vynnimu"]:
		if not banded.has(species):
			return "the %s of Ivenwhal Wudhen don't band into a pack" % species
	return ""


## A disc with the pack flow's wild monsters (PACK_SPOTS), with the packs or, not `packed`,
## without.
static func _pack_state(packed: bool) -> GameState:
	var region: Region = Region.disc(8)
	var hp: Dictionary[String, int] = {}
	for spot: Vector2i in PACK_SPOTS:
		region.wild_monsters.append(spot)
		region.add_placement(WildSpotPlacements.KIND, spot, WildSpot.NAMED + PACK_SPOTS[spot])
		hp[PACK_SPOTS[spot]] = 10
	var ordered: Array[Feature] = _wild_features(hp, PACK_TRAITS)
	if packed:
		ordered.append(PackFeature.new(PACK_TYPES))
	return GameState.new(region, SEED, ordered)


## The entity ids of `state`'s wild monsters of `species`, standing or fainted, in id order.
static func _monsters_of(state: GameState, species: String) -> Array[int]:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var found: Array[int] = []
	for monster: int in wild.monsters + wild.fainted:
		if wild.species_of(monster) == species:
			found.append(monster)
	found.sort()
	return found
