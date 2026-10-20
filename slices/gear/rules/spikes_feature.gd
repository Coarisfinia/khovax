class_name SpikesFeature
extends Feature
## Spikes (owner, #223, #692): with spikes in their trap slot, a player's ring hurts the wild
## monsters pushing on it, once every STRIKE_TICKS, for the spikes' damage. Pushing means sealing
## in it (#219) or encircled by it while it waits for a totem, striking its wall (#422). Like a
## companion's auto attack (#221), the hurt is non-lethal: it never takes a wild monster below 1 HP,
## and it weakens one sealing, so it pushes less (RingSealing.pressure). The ring is its
## dominator's, so their spikes count. Each hurt raises SpikesStruck.
##
## The gear is the player's, kept in their profile outside the simulation, so a change of what's in
## their trap slot comes in as a request from their profile's outbox (#818, OutboxEntry.TRAP), and
## this keeps the trap in their entry of the player's world store (#724): it lasts between sessions
## and goes with them from instance to instance. The ids of the requests it applied are kept there
## too (OutboxReceipts), so one sent again changes nothing. The strikes fall on the instance's
## ticks.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "spikes"
## The ticks between two hurts of the spikes, as between two auto attacks.
const STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND
## The key of the trap's code (code_of) in a player's store entry: none for an empty trap slot.
const TRAP: String = "trap"

## Each spikes' damage, by the code of its gear id (code_of), from the gear's content data (the
## gear slice reads it).
var damages: Dictionary[int, int] = {}


func _init(spikes_damages: Dictionary[int, int] = {}) -> void:
	damages = spikes_damages


func id() -> String:
	return ID


## The wild monsters' HP, which the health feature keeps (#835), and the rings.
func requires() -> Array[String]:
	var needed: Array[String] = [HealthFeature.ID, DominationFeature.ID]
	return needed


## The wild monsters it wounds, which an instance without wild monster spots lacks (#884): no ring
## holds any there.
func after() -> Array[String]:
	var earlier: Array[String] = [WildMonsterFeature.ID]
	return earlier


## The code a request carries for the gear `gear_id` in the trap slot (CommandCodes):
## CommandCodes.NONE for none, never for a piece of gear (the gear's content files it with
## CommandCodes.file).
static func code_of(gear_id: String) -> int:
	return CommandCodes.of(gear_id)


## The code of the gear in the trap slot a player's store entry `entry` of this feature holds
## (code_of), or CommandCodes.NONE.
static func trap_of(entry: Dictionary) -> int:
	var code: int = entry.get(TRAP, CommandCodes.NONE)
	return code


## Takes every player's change of their trap, in slot order, then lets every ring's spikes, in its
## dominator's id order, hurt the wild monsters pushing on it, on every STRIKE_TICKS-th tick.
func step(state: GameState, commands: Array[Command]) -> void:
	_change_traps(state, commands)
	if state.tick % STRIKE_TICKS != 0:
		return
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return
	var rings: Dictionary[int, Array] = {}
	for dominator_id: int in domination.seals:
		rings[dominator_id] = domination.seals[dominator_id].monsters
	for dominator_id: int in domination.encircled:
		rings[dominator_id] = domination.encircled[dominator_id]
	var dominators: Array[int] = []
	dominators.assign(rings.keys())
	dominators.sort()
	for dominator_id: int in dominators:
		var damage: int = _damage_of(state, dominator_id)
		if damage == 0:
			continue
		for monster_id: int in rings[dominator_id].duplicate():
			_hurt(state, wild, monster_id, dominator_id, damage)


## The spikes of `dominator_id`'s ring hurt `monster_id` for `damage`, never below 1 HP.
static func _hurt(
		state: GameState,
		wild: WildMonsterFeature,
		monster_id: int,
		dominator_id: int,
		damage: int,
) -> void:
	wild.wound(state, monster_id, damage)
	state.events.append(SpikesStruck.new(monster_id, dominator_id, damage))


## Puts the gear each player here asks for into their trap, in slot order, unless its request was
## applied before. A code of no spikes this build knows is kept all the same: it hurts nothing.
func _change_traps(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var changing: bool = command != null and command.request_kind == OutboxEntry.TRAP
		if not changing or state.player(slot) == null:
			continue
		if not OutboxReceipts.take(state, slot, id(), command):
			continue
		var entry: Dictionary = state.store(slot, id())
		if command.request_data == CommandCodes.NONE:
			var _emptied: bool = entry.erase(TRAP)
		else:
			entry[TRAP] = command.request_data


## The damage of the spikes in the trap of the dominator `dominator_id`, or 0.
func _damage_of(state: GameState, dominator_id: int) -> int:
	var dominator: Entity = state.entity(dominator_id)
	if dominator == null or dominator.slot == Entity.NO_SLOT:
		return 0
	return damages.get(trap_of(state.stored(dominator.slot, id())), 0)
