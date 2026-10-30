extends RefCounted
## Host settings flow (#1309): the world's host (slot 0) chooses its settings with requests from
## their profile's outbox, each applied once and on the tick it comes; another player's request of
## the kind is acknowledged and changes nothing, and so is a choice there is none of. The difficulty
## (#1315): Standard plays Tuning's numbers as they are; Easy makes the wild monsters weaker by
## ×0.70 and Hard stronger by ×1.30: their strength, the damage they take (their HP), their pace and
## the ring's power against them. The world settings (#1316), which the difficulty leaves alone:
## the drop rate scales the loot rolls, at least one where there were any, and the instance reset
## delay is how long the world keeps an instance nobody is in. Revive on waystones (#1891) starts
## off, and the host turns it on; a choice there is none of is refused.

## A species the flow makes up, with round numbers.
const BEAST: String = "test_beast"
const BEAST_HP: int = 100
const BEAST_STRENGTH: int = 1000

## Each player's outbox, by slot, as their profiles would hold them.
var _outboxes: Array[Outbox] = [Outbox.new(), Outbox.new()]


func run(_tree: SceneTree) -> String:
	var state: GameState = _state()
	var problem: String = _check_at(state, [HostSettings.STANDARD, BEAST_STRENGTH, 20, 36_000, 7])
	if not problem.is_empty():
		return "at first: " + problem
	var events: Array[RefCounted] = _ask(state, 1, HostSettings.HARD)
	if HostSettings.difficulty(state) != HostSettings.STANDARD or not _acknowledged(events, 1):
		return "another player's request changed the difficulty, or wasn't acknowledged"
	var _asked: Array[RefCounted] = _ask(state, 0, HostSettings.EASY)
	problem = _check_at(state, [HostSettings.EASY, 700, 28, 51_428, 10])
	if not problem.is_empty():
		return "at Easy: " + problem
	_asked = _ask(state, 0, 500)
	if HostSettings.difficulty(state) != HostSettings.EASY:
		return "a difficulty there is none of was taken"
	var hard: Command = _command(0, HostSettings.HARD)
	Simulation.step(state, [hard, null])
	problem = _check_at(state, [HostSettings.HARD, 1300, 15, 27_692, 5])
	if not problem.is_empty():
		return "at Hard: " + problem
	_asked = _ask(state, 0, HostSettings.STANDARD)
	# The Hard request sent again, as an outbox does until it's acknowledged, changes nothing.
	Simulation.step(state, [hard, null])
	if HostSettings.difficulty(state) != HostSettings.STANDARD:
		return "a request sent again was applied twice"
	return _check_drops(state)


## The drop rate halves and doubles the loot rolls, never below one where there were any; the
## difficulty doesn't change them.
func _check_drops(state: GameState) -> String:
	var _asked: Array[RefCounted] = _ask(state, 0, HostSettings.HARD)
	var rolls: Array[int] = [HostSettings.drops(state, 0), HostSettings.drops(state, 3)]
	_asked = _ask_for(state, HostSettings.DROP_RATE, 500)
	rolls.append_array([HostSettings.drops(state, 1), HostSettings.drops(state, 3)])
	_asked = _ask_for(state, HostSettings.DROP_RATE, 2000)
	rolls.append_array([HostSettings.drops(state, 0), HostSettings.drops(state, 3)])
	if rolls != [0, 3, 1, 1, 0, 6] or HostSettings.difficulty(state) != HostSettings.HARD:
		return "the drop rate gives rolls %s, or changed the difficulty" % [rolls]
	return _check_reset_delay()


## A fresh world keeps an instance nobody is in for Tuning's delay; once the host chooses 15
## minutes, for 15 minutes.
func _check_reset_delay() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, FlowSteps.BASIC)
	var before: int = world.purge_ticks()
	world.step([_command_for(0, HostSettings.RESET_DELAY, 15)])
	var after: int = world.purge_ticks()
	if before != World.PURGE_TICKS or after != 15 * 60 * Simulation.TICKS_PER_SECOND:
		return "the world keeps a left instance %d ticks, then %d after 15 minutes" % [
			before,
			after,
		]
	return _check_revive_toggle()


## Revive on waystones starts off; the host turns it on, and a choice there is none of is refused.
func _check_revive_toggle() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, FlowSteps.BASIC)
	var state: GameState = world.instances[FlowSteps.BASIC]
	var off: bool = not HostSettings.revives_on_waystones(state)
	world.step([_command_for(0, HostSettings.REVIVE_ON_WAYSTONES, HostSettings.ON)])
	var on: bool = HostSettings.revives_on_waystones(state)
	world.step([_command_for(0, HostSettings.REVIVE_ON_WAYSTONES, 2)])
	if not off or not on or not HostSettings.revives_on_waystones(state):
		return "revive on waystones didn't start off, turn on, or refuse a bad choice"
	return _check_presets()


## The difficulty presets (#1892): picking each one sets its settings, changing the toggle or the
## factor shows Custom, and picking the preset again leaves Custom; a step from Custom lands on the
## preset with the factor first.
func _check_presets() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, FlowSteps.BASIC)
	var host: PlayerStore = world.stores[HostSettings.HOST]
	if HostSettings.preset_of(_preset_values(host)) != 1:
		return "a fresh world isn't on Standard"
	var revives: Array[int] = [HostSettings.ON, HostSettings.OFF, HostSettings.OFF]
	for preset: int in HostSettings.PRESETS.size():
		var problem: String = _check_preset(world, preset, revives[preset])
		if not problem.is_empty():
			return problem
	var from_custom: Dictionary[String, int] = {
		HostSettings.DIFFICULTY: HostSettings.HARD,
		HostSettings.REVIVE_ON_WAYSTONES: HostSettings.ON,
	}
	var steps: Array[int] = [
		HostSettings.preset_step(from_custom, 1),
		HostSettings.preset_step(from_custom, -1),
		HostSettings.preset_step(from_custom, -2),
	]
	if steps != [2, 2, 1]:
		return "stepping from Custom lands on the presets %s" % [steps]
	return ""


## Picking `preset` in `world` sets the factor and revive on waystones to `revive`; changing either
## so no preset matches shows Custom, and picking `preset` again leaves it.
func _check_preset(world: World, preset: int, revive: int) -> String:
	var host: PlayerStore = world.stores[HostSettings.HOST]
	_pick(world, preset)
	var values: Dictionary[String, int] = _preset_values(host)
	var wanted: Dictionary[String, int] = {
		HostSettings.DIFFICULTY: HostSettings.DIFFICULTIES[preset],
		HostSettings.REVIVE_ON_WAYSTONES: revive,
	}
	if HostSettings.preset_of(values) != preset or values != wanted:
		return "picking preset %d sets %s" % [preset, values]
	# A change that matches no preset: a factor that matches another preset's with this toggle
	# (Standard to Hard, both off) shows that preset instead.
	var others: Dictionary[String, int] = {
		HostSettings.DIFFICULTY: HostSettings.STANDARD if preset == 0 else HostSettings.EASY,
		HostSettings.REVIVE_ON_WAYSTONES: HostSettings.ON - revive,
	}
	for setting: String in others:
		world.step([_command_for(0, setting, others[setting])])
		var custom: int = HostSettings.preset_of(_preset_values(host))
		_pick(world, preset)
		var again: int = HostSettings.preset_of(_preset_values(host))
		if custom != HostSettings.CUSTOM or again != preset:
			return "changing %s on preset %d shows %d, then %d" % [setting, preset, custom, again]
	return ""


## Steps `world` with the host's requests for `preset`, one a tick.
func _pick(world: World, preset: int) -> void:
	var host: PlayerStore = world.stores[HostSettings.HOST]
	for data: int in HostSettings.preset_requests(_preset_values(host), preset):
		var setting: String = HostSettings.setting_of(data)
		world.step([_command_for(0, setting, HostSettings.value_of(data))])


## The settings a preset sets, as the host's world store `host` keeps them.
func _preset_values(host: PlayerStore) -> Dictionary[String, int]:
	return HostSettings.preset_values(host.stored(HostSettings.FEATURE_ID))


## A disc with one wild monster of BEAST in its middle, the host and another player beside it.
func _state() -> GameState:
	var region: Region = Region.disc(4)
	region.wild_monsters = [Vector2i.ZERO]
	region.add_placement(WildSpotPlacements.KIND, Vector2i.ZERO, WildSpot.NAMED + BEAST)
	var ordered: Array[Feature] = [
		HostSettingsFeature.new(),
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new({ BEAST: BEAST_HP }),
		WildMonsterFeature.new([], [], { BEAST: BEAST_STRENGTH }),
	]
	var state: GameState = GameState.new(region, 1, ordered)
	var _host: Entity = state.add_entity(0, Vector2i(3, 0))
	var _guest: Entity = state.add_entity(1, Vector2i(-3, 0))
	return state


## Why the state doesn't play as `wanted` says, or "": its difficulty, the monster's strength, its
## steps' pace, a level-one ring's power against it, and the HP a hit of 7 takes off it.
func _check_at(state: GameState, wanted: Array[int]) -> String:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var monster: int = wild.monsters[0]
	var before: int = health.hp_of(state, monster)
	var _fell: bool = health.hurt(state, monster, 7)
	var shown: Array[int] = [
		HostSettings.difficulty(state),
		wild.strength_of(state, monster),
		WildPace.paced(state, WildMonsterFeature.STEP_TICKS, 0),
		HostSettings.ring_power(state, RingSealing.ring_power(RingSealing.PLAYER_LEVEL)),
		before - health.hp_of(state, monster),
	]
	health.heal(state, monster, BEAST_HP)
	if shown != wanted:
		return "difficulty, strength, pace, ring power and HP taken are %s, not %s" % [
			shown,
			wanted,
		]
	return ""


## Steps `state` one tick with the player in `slot` asking for the difficulty `value`; returns the
## tick's events.
func _ask(state: GameState, slot: int, value: int) -> Array[RefCounted]:
	var commands: Array[Command] = [null, null]
	commands[slot] = _command(slot, value)
	Simulation.step(state, commands)
	return state.events


## Steps `state` one tick with the host asking for `setting` to be `value`; returns the tick's
## events.
func _ask_for(state: GameState, setting: String, value: int) -> Array[RefCounted]:
	Simulation.step(state, [_command_for(0, setting, value), null])
	return state.events


## A command of the player in `slot` carrying a new request from their outbox for the difficulty
## `value`.
func _command(slot: int, value: int) -> Command:
	return _command_for(slot, HostSettings.DIFFICULTY, value)


## A command of the player in `slot` carrying a new request from their outbox for `setting` to be
## `value`.
func _command_for(slot: int, setting: String, value: int) -> Command:
	var data: int = HostSettings.request_data(setting, value)
	var command: Command = Command.new()
	_outboxes[slot].post(OutboxEntry.HOST_SETTING, data).fill(command)
	return command


## Whether `events` acknowledge a request of the player in `slot`.
func _acknowledged(events: Array[RefCounted], slot: int) -> bool:
	for event: RefCounted in events:
		if event is RequestApplied and (event as RequestApplied).slot == slot:
			return true
	return false
