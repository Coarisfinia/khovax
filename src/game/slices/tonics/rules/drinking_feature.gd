class_name DrinkingFeature
extends Feature
## Drinking a tonic or a draught (#2310, the potion design on #2049, section 6): a tonic helps the
## player's out companion, a draught the player themselves. Drinking one is a request from their
## profile's outbox (#818, OutboxEntry.DRINK) whose data is the brew's code (`code_of`), posted as
## the brew is spent from the profile (TonicDrinking), so it's applied once (OutboxReceipts). A Mend
## (TonicDose.mend) heals its target at once by its share of their full HP, at least 1 HP
## (HealthFeature.heal). Every other brew is drunk all the same but does nothing yet: the timed
## effects are #2311, Shared and Slow-release #2312. After a drink the player waits WAIT_TICKS
## before the next. A request this can't carry out (an unknown brew, no target that can use it, or
## while waiting) is acknowledged and changes nothing; the profile refuses those before spending
## (`problem`).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "drinking"
## How long a player waits between two drinks. Its number is in Tuning (#1309).
const WAIT_TICKS: int = Tuning.DRINK_WAIT_TICKS

## What each brew does, by its code (`code_of`), from the tonics' content data.
var doses: Dictionary[int, TonicDose] = {}
## The ticks each player still waits before their next drink, by their entity id.
var _waits: Dictionary[int, int] = {}


func _init(brew_doses: Dictionary[int, TonicDose] = {}) -> void:
	doses = brew_doses


func id() -> String:
	return ID


## The HP it heals, the knockdowns, whose downed players drink no draught, and the companions,
## whose out one drinks a tonic.
func requires() -> Array[String]:
	var needed: Array[String] = [KnockdownFeature.ID, HealthFeature.ID, CompanionFeature.ID]
	return needed


## The code a request carries for the brew `brew_id` (CommandCodes): the tonics' content files
## every one with CommandCodes.file, so no two share one.
static func code_of(brew_id: String) -> int:
	return CommandCodes.of(brew_id)


## Counts every player's wait down, then carries out each drink the players here ask for, in slot
## order, unless its request was applied before.
func step(state: GameState, commands: Array[Command]) -> void:
	for entity_id: int in _waits.keys():
		if _waits[entity_id] <= 1:
			var _done: bool = _waits.erase(entity_id)
		else:
			_waits[entity_id] -= 1
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var drinking: bool = command != null and command.request_kind == OutboxEntry.DRINK
		if not drinking or state.player(slot) == null:
			continue
		if OutboxReceipts.take(state, slot, id(), command):
			_drink(state, slot, command.request_data)


## The player in `slot` drinks the brew `code`, if they can: its target is helped and they wait.
func _drink(state: GameState, slot: int, code: int) -> void:
	var dose: TonicDose = doses.get(code)
	if dose == null or not problem(state, slot, dose.for_player).is_empty():
		return
	_waits[state.player(slot).id] = WAIT_TICKS
	if dose.mend > 0:
		var target_id: int = target_of(state, slot, dose.for_player)
		var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
		var full_hp: int = health.max_hp_of(state, target_id)
		health.heal(state, target_id, maxi(1, Fixed.scale(full_hp, dose.mend)))


## Why the player in `slot` can't drink a brew now, a draught (`for_player`) or a tonic, or "":
## they're here, not waiting, and its target can use it.
func problem(state: GameState, slot: int, for_player: bool) -> String:
	var player: Entity = state.player(slot)
	if player == null:
		return "no player drinks here"
	if _waits.has(player.id):
		return "wait %d s before the next drink" % Fixed.div_floor(
			_waits[player.id] + Simulation.TICKS_PER_SECOND - 1,
			Simulation.TICKS_PER_SECOND,
		)
	if target_of(state, slot, for_player) == 0:
		return "a knocked-down player can't drink" if for_player else "no companion is out"
	return ""


## The entity a draught (`for_player`) or a tonic of the player in `slot` helps: the player unless
## they're knocked down, or their out companion; 0 for none.
static func target_of(state: GameState, slot: int, for_player: bool) -> int:
	var player: Entity = state.player(slot)
	if player == null:
		return 0
	if for_player:
		var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
		return 0 if knockdown.is_down(player.id) else player.id
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	return companions.companion_of(slot)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _waits.erase(removed_id)


func hash_values() -> Array[int]:
	return DataReader.flat_pairs(_waits)


func save_values() -> Dictionary:
	return { "waits": DataReader.flat_pairs(_waits) }


## Each waiting player must be in the restored instance, a player, waiting from 1 to WAIT_TICKS.
func load_values(state: GameState, values: DataReader) -> void:
	_waits.clear()
	var loaded: Dictionary[int, int] = values.pairs("waits", 1, DataReader.MOST)
	if values.failed():
		return
	for entity_id: int in loaded:
		var entity: Entity = state.entity(entity_id)
		if entity == null or entity.slot == Entity.NO_SLOT or loaded[entity_id] > WAIT_TICKS:
			values.fail("waiting player %d isn't in the instance or waits too long" % entity_id)
			return
		_waits[entity_id] = loaded[entity_id]
