class_name MovementFeature
extends Feature
## Walking tile by tile, for every entity with a walk (its movement component): a move command
## starts a step to the neighboring tile, which takes MOVE_TICKS ticks to arrive. A move that
## arrives is followed by the next one in the same tick, so a held direction walks without pauses.
## The grid's edge stops a walker. Each started step raises an EntityMoved event. Walkers go in
## entity id order, each moved by the command of the player slot that owns it.

## Ticks to walk from one tile to the next.
const MOVE_TICKS: int = 6

## Every walking entity's walk, by entity id. Players get one when they are added; other entities
## get one from the rule that adds them.
var walks: Dictionary[int, Walk] = {}


func id() -> int:
	return Features.MOVEMENT


func step(state: GameState, commands: Array[Command]) -> void:
	for walker: Entity in state.entities:
		var current: Walk = walks.get(walker.id)
		if current == null:
			continue
		if current.ticks_left > 0:
			current.ticks_left -= 1
		var command: Command = Command.of(commands, walker.slot)
		if command != null and not current.is_moving():
			_start_move(state, walker, current, command)


func entity_added(_state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		walks[added.id] = Walk.new(added.tile)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = walks.erase(removed_id)


## The entity's walk, or null when it doesn't walk.
func walk(entity_id: int) -> Walk:
	return walks.get(entity_id)


func hash_values() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(walks.keys())
	ids.sort()
	var values: Array[int] = [ids.size()]
	for each: int in ids:
		values.append(each)
		values.append(walks[each].from.x)
		values.append(walks[each].from.y)
		values.append(walks[each].ticks_left)
	return values


func _start_move(state: GameState, walker: Entity, current: Walk, command: Command) -> void:
	if command.move < 0 or command.move >= Hex.DIRECTIONS.size():
		return
	var next: Vector2i = walker.tile + Hex.DIRECTIONS[command.move]
	if not state.has_tile(next):
		return
	current.from = walker.tile
	walker.tile = next
	current.ticks_left = MOVE_TICKS
	state.events.append(EntityMoved.new(walker.id, current.from, next))
