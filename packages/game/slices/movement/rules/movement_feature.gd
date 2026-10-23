class_name MovementFeature
extends Feature
## Walking tile by tile, for every entity with a walk (its movement component): a move command
## starts a step to the neighboring tile, which takes MOVE_TICKS ticks to arrive. A move that
## arrives is followed by the next one in the same tick, so a held direction walks without pauses.
## The region's edge, water and rock stop a walker, and so does a tile where something that doesn't
## walk stands (a wild monster, #19); walkers walk through each other, so co-op players never block
## one another, and a companion (#338) never traps its player. Each started step raises an
## EntityMoved event. Walkers go in entity id order, each player moved by the command of their
## slot; a walker no player controls (a companion) is moved by its own rule, through `try_step`.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "movement"
## Ticks to walk from one tile to the next.
const MOVE_TICKS: int = 6

## Every walking entity's walk, by entity id. Players get one when they are added; other entities
## get one from the rule that adds them.
var walks: Dictionary[int, Walk] = {}
## The walkers held still by a later rule (`hold`), by entity id.
var held: Dictionary[int, bool] = {}


func id() -> String:
	return ID


func step(state: GameState, commands: Array[Command]) -> void:
	for walker: Entity in state.entities:
		var current: Walk = walks.get(walker.id)
		if current == null:
			continue
		if current.ticks_left > 0:
			current.ticks_left -= 1
		var command: Command = Command.of(commands, walker.slot)
		if command != null and not current.is_moving() and not held.has(walker.id):
			var _started: bool = _start_move(state, walker, current, command.move)


func entity_added(_state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		walks[added.id] = Walk.new(added.tile)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = walks.erase(removed_id)
	_dropped = held.erase(removed_id)


## Holds the walker `entity_id` still, or lets it walk again: a later rule's (a knocked-down
## player, #479, or a companion holding its special, #1167). Neither commands nor `try_step` start
## its steps while held; a step already under way ends. The rule that holds it keeps that in its
## own state and holds it again on loading.
func hold(entity_id: int, on: bool) -> void:
	if on:
		held[entity_id] = true
	else:
		var _released: bool = held.erase(entity_id)


## Gives `added`, an entity no player controls, a walk, standing on its tile: its own rule moves
## it with `try_step` (a companion, #338).
func add_walk(added: Entity) -> void:
	walks[added.id] = Walk.new(added.tile)


## Starts a step of `walker`, which has a walk, toward the neighbor in `direction`, if it stands
## and nothing stops it there; returns whether it started.
func try_step(state: GameState, walker: Entity, direction: int) -> bool:
	var current: Walk = walks.get(walker.id)
	if current == null or current.is_moving() or held.has(walker.id):
		return false
	return _start_move(state, walker, current, direction)


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


## Each walk as its entity's id, the tile its move started from and the ticks left, in id order.
func save_values() -> Dictionary:
	var ids: Array[int] = []
	ids.assign(walks.keys())
	ids.sort()
	var flat: Array[int] = []
	for each: int in ids:
		flat.append_array([each, walks[each].from.x, walks[each].from.y, walks[each].ticks_left])
	return { "walks": flat }


func load_values(state: GameState, values: DataReader) -> void:
	walks.clear()
	var flat: Array[int] = values.wholes("walks", -DataReader.MOST, DataReader.MOST)
	if flat.size() % 4 != 0:
		values.fail("a walk is cut off")
		return
	for i: int in range(0, flat.size(), 4):
		var from: Vector2i = Vector2i(flat[i + 1], flat[i + 2])
		var ticks_left: int = flat[i + 3]
		if state.entity(flat[i]) == null or walks.has(flat[i]) or not state.region.has_tile(from):
			values.fail("walk %d isn't of one entity or starts off the region" % flat[i])
			return
		if ticks_left < 0 or ticks_left > MOVE_TICKS:
			values.fail("walk %d has %d ticks left" % [flat[i], ticks_left])
			return
		walks[flat[i]] = _walk_from(from, ticks_left)


static func _walk_from(from: Vector2i, ticks_left: int) -> Walk:
	var restored: Walk = Walk.new(from)
	restored.ticks_left = ticks_left
	return restored


func _start_move(state: GameState, walker: Entity, current: Walk, direction: int) -> bool:
	if direction < 0 or direction >= Hex.DIRECTIONS.size():
		return false
	var next: Vector2i = walker.tile + Hex.DIRECTIONS[direction]
	if not state.region.is_walkable(next) or is_occupied(state, next):
		return false
	current.from = walker.tile
	walker.tile = next
	current.ticks_left = MOVE_TICKS
	state.events.append(EntityMoved.new(walker.id, current.from, next))
	return true


## Whether something that doesn't walk (a wild monster) stands on the tile, which stops walkers.
func is_occupied(state: GameState, tile: Vector2i) -> bool:
	for other: Entity in state.entities:
		if other.tile == tile and not walks.has(other.id):
			return true
	return false
