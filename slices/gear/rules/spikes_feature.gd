class_name SpikesFeature
extends Feature
## Spikes (owner, #223, #692): with spikes in their trap slot, a player's ring hurts the wild
## monsters pushing on it, once every STRIKE_TICKS, for the spikes' damage. Pushing means sealing
## in it (#219) or encircled by it while it waits for a totem, striking its wall (#422). Like a
## companion's auto attack (#221), the hurt is non-lethal: it never takes a wild monster below 1 HP,
## and it weakens one sealing, so it pushes less (RingSealing.pressure). The ring is its
## dominator's, so their spikes count. Each hurt raises SpikesStruck.
##
## The gear is the player's, kept in their profile outside the simulation, so it comes in through
## their command (Command.trap), which carries it every tick. It keeps no state of its own: the
## strikes fall on the instance's ticks.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "spikes"
## The ticks between two hurts of the spikes, as between two auto attacks.
const STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND

## Each spikes' damage, by the code of its gear id (code_of), from the gear's content data (the
## gear slice reads it).
var damages: Dictionary[int, int] = {}


func _init(spikes_damages: Dictionary[int, int] = {}) -> void:
	damages = spikes_damages


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, DominationFeature.ID]
	return needed


## The code a command carries for the gear `gear_id` in the trap slot (CommandCodes):
## Command.NO_TRAP for none, never for a piece of gear (the gear's content files it with
## CommandCodes.file).
static func code_of(gear_id: String) -> int:
	return CommandCodes.of(gear_id)


## Lets every ring's spikes, in its dominator's id order, hurt the wild monsters pushing on it, on
## every STRIKE_TICKS-th tick.
func step(state: GameState, commands: Array[Command]) -> void:
	if state.tick % STRIKE_TICKS != 0:
		return
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var rings: Dictionary[int, Array] = {}
	for dominator_id: int in domination.seals:
		rings[dominator_id] = domination.seals[dominator_id].monsters
	for dominator_id: int in domination.encircled:
		rings[dominator_id] = domination.encircled[dominator_id]
	var dominators: Array[int] = []
	dominators.assign(rings.keys())
	dominators.sort()
	for dominator_id: int in dominators:
		var damage: int = _damage_of(state, commands, dominator_id)
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


## The damage of the spikes the dominator `dominator_id` carries in their command, or 0.
func _damage_of(state: GameState, commands: Array[Command], dominator_id: int) -> int:
	var dominator: Entity = state.entity(dominator_id)
	var command: Command = Command.of(commands, dominator.slot) if dominator != null else null
	return damages.get(command.trap, 0) if command != null else 0
