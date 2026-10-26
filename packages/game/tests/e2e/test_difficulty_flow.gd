extends RefCounted
## Difficulty flow (#1315): the world's host (slot 0) chooses the difficulty with a request from
## their profile's outbox, applied once and on the tick it comes; another player's request of the
## kind is acknowledged and changes nothing, and so is a choice there is none of. Standard plays
## Tuning's numbers as they are; Easy makes the wild monsters weaker by ×0.70 and Hard stronger by
## ×1.30: their strength, the damage they take (their HP), their pace and the ring's power against
## them.

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
	return ""


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


## A command of the player in `slot` carrying a new request from their outbox for the difficulty
## `value`.
func _command(slot: int, value: int) -> Command:
	var data: int = HostSettings.request_data(HostSettings.DIFFICULTY, value)
	var command: Command = Command.new()
	_outboxes[slot].post(OutboxEntry.HOST_SETTING, data).fill(command)
	return command


## Whether `events` acknowledge a request of the player in `slot`.
func _acknowledged(events: Array[RefCounted], slot: int) -> bool:
	for event: RefCounted in events:
		if event is RequestApplied and (event as RequestApplied).slot == slot:
			return true
	return false
