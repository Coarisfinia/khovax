class_name KnockdownFeature
extends Feature
## Knocked down in co-op (#479): a player at 0 HP with an ally within ALLY_RANGE kneels and can't
## move (the health rule knocks them down with `knock_down`). An ally standing next to them for
## REVIVE_TICKS in a row revives them (PlayerRevived); standing away starts that over. Nobody
## revives them within DOWN_TICKS, and they go back to the world's spawn (SentToSpawn, #457).

## How near an ally has to be for a fallen player to be knocked down rather than sent back.
const ALLY_RANGE: int = 200
## How long an ally stands beside a knocked-down player to revive them.
const REVIVE_TICKS: int = 3 * Simulation.TICKS_PER_SECOND
## How long a knocked-down player waits before going back to the spawn.
const DOWN_TICKS: int = 30 * Simulation.TICKS_PER_SECOND

## Each knocked-down player's ticks down and ticks of reviving so far, by entity id.
var _down: Dictionary[int, Vector2i] = {}
var _movement: MovementFeature


func id() -> int:
	return Features.KNOCKDOWN


func requires() -> Array[int]:
	return [Features.MOVEMENT]


func start(state: GameState) -> void:
	_movement = state.feature(Features.MOVEMENT) as MovementFeature


## Each knocked-down player, in id order: revived once an ally has stood beside them long enough,
## sent back once they have waited too long.
func step(state: GameState, _commands: Array[Command]) -> void:
	var downed: Array[int] = knocked_down()
	for entity_id: int in downed:
		var player: Entity = state.entity(entity_id)
		var counts: Vector2i = _down[entity_id]
		counts.x += 1
		counts.y = counts.y + 1 if _ally_beside(state, player) else 0
		_down[entity_id] = counts
		if counts.y >= REVIVE_TICKS:
			_revive(state, entity_id)
		elif counts.x >= DOWN_TICKS:
			_send_back(state, player)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _down.erase(removed_id)


## Whether the player `player` in `state` has an ally within ALLY_RANGE who could revive them: one
## who isn't knocked down themselves.
func has_ally_near(state: GameState, player: Entity) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var ally: Entity = state.player(slot)
		if ally != null and ally.id != player.id and not is_down(ally.id):
			if Hex.distance(ally.tile, player.tile) <= ALLY_RANGE:
				return true
	return false


## Knocks the player `entity_id` down: they kneel and are held still until revived or sent back.
func knock_down(entity_id: int) -> void:
	_down[entity_id] = Vector2i.ZERO
	_movement.hold(entity_id, true)


## Whether the player `entity_id` is knocked down.
func is_down(entity_id: int) -> bool:
	return _down.has(entity_id)


## The knocked-down players' entity ids, in id order.
func knocked_down() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_down.keys())
	ids.sort()
	return ids


## How far a knocked-down player's revive has come, from 0 to REVIVE_TICKS, for the look.
func revive_ticks(entity_id: int) -> int:
	return _down.get(entity_id, Vector2i.ZERO).y


## Gets the player `entity_id` back on their feet: revived by an ally.
func _revive(state: GameState, entity_id: int) -> void:
	_get_up(entity_id)
	state.events.append(PlayerRevived.new(entity_id))


## Sends `player` back to the world's spawn: nobody revived them in time.
func _send_back(state: GameState, player: Entity) -> void:
	_get_up(player.id)
	state.events.append(SentToSpawn.new(player.id, player.slot))


func _get_up(entity_id: int) -> void:
	var _dropped: bool = _down.erase(entity_id)
	_movement.hold(entity_id, false)


func _ally_beside(state: GameState, player: Entity) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var ally: Entity = state.player(slot)
		if ally != null and ally.id != player.id and not is_down(ally.id):
			if Hex.distance(ally.tile, player.tile) == 1:
				return true
	return false


func hash_values() -> Array[int]:
	var values: Array[int] = [_down.size()]
	for entity_id: int in knocked_down():
		values.append_array([entity_id, _down[entity_id].x, _down[entity_id].y])
	return values


func save_values() -> Dictionary:
	var downed: Array[int] = knocked_down()
	var counts: Array[int] = []
	for entity_id: int in downed:
		counts.append_array([_down[entity_id].x, _down[entity_id].y])
	return { "down": downed, "counts": counts }


## Each knocked-down player must be a player in the instance, once, with counts below the limits;
## they're held still again.
func load_values(state: GameState, values: DataReader) -> void:
	_down.clear()
	var downed: Array[int] = values.wholes("down", 1, DataReader.MOST)
	var counts: Array[int] = values.wholes("counts", 0, DOWN_TICKS)
	if values.failed():
		return
	if counts.size() != downed.size() * 2:
		values.fail("the knocked-down players and their counts don't match")
		return
	for i: int in downed.size():
		var player: Entity = state.entity(downed[i])
		var waited: Vector2i = Vector2i(counts[i * 2], counts[i * 2 + 1])
		# Revived for no longer than they've been down.
		var fits: bool = waited.x < DOWN_TICKS and waited.y < REVIVE_TICKS and waited.y <= waited.x
		if player == null or player.slot == Entity.NO_SLOT or _down.has(downed[i]) or not fits:
			values.fail("knocked-down player %d isn't one player in the instance" % downed[i])
			return
		knock_down(downed[i])
		_down[downed[i]] = waited
