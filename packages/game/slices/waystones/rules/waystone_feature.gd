class_name WaystoneFeature
extends Feature
## Waystones (#1854, #1890): standing stones a region piece places as a tile of their own kind,
## which nobody walks. A player who comes next to one activates it for themselves (each player their
## own, #74): it becomes their respawn point (RespawnPoint), where the world sends them back when
## they fall with nobody to revive them, and it's added to the waystones they activated, kept in
## their world store, which the look lights up. The game saves itself, so a waystone saves nothing
## else. A knocked-down player activates nothing. Brought by a region that has a waystone
## (RegionFeatures).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "waystones"
## The waystone's tile kind, its tile blueprint's id.
const KIND: String = "waystone"
## The key of the waystones a player activated in their entry: a list of [instance, q, r].
const ACTIVATED: String = "activated"

## The instance's blueprint id, which a respawn point names.
var instance_name: String


func _init(instance_id: String = "") -> void:
	instance_name = instance_id


func id() -> String:
	return ID


func after() -> Array[String]:
	var read: Array[String] = [KnockdownFeature.ID]
	return read


## Whether `region` has a waystone.
static func has_waystone(region: Region) -> bool:
	return region.terrain.values().has(KIND)


## Every player next to a waystone, in slot order, activates it: the first one beside them in
## direction order.
func step(state: GameState, _commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null and not _is_down(state, player):
			var stone: Vector2i = beside(state.region, player.tile)
			if stone != player.tile:
				_activate(state, player, stone)


## Whether `player` is knocked down in `state`, where they activate nothing.
static func _is_down(state: GameState, player: Entity) -> bool:
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	return knockdown != null and knockdown.is_down(player.id)


## The first waystone next to `tile` in `region`, in direction order, or `tile` itself for none.
static func beside(region: Region, tile: Vector2i) -> Vector2i:
	for direction: Vector2i in Hex.DIRECTIONS:
		if region.terrain.get(tile + direction, "") == KIND:
			return tile + direction
	return tile


## The waystones the player in `slot` activated in the instance `instance_id`, as `state` holds
## their world store, for the look.
static func activated_in(state: GameState, slot: int, instance_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var listed: Variant = state.stored(slot, ID).get(ACTIVATED, [])
	if not listed is Array:
		return tiles
	var stones: Array = listed
	for stone: Variant in stones:
		if not stone is Array:
			continue
		var parts: Array = stone
		if parts.size() == 3 and parts[0] == instance_id and parts[1] is int and parts[2] is int:
			var q: int = parts[1]
			var r: int = parts[2]
			tiles.append(Vector2i(q, r))
	return tiles


## Makes `stone` the respawn point of `player`, and adds it to the waystones they activated; raises
## WaystoneActivated when it wasn't their respawn point yet.
func _activate(state: GameState, player: Entity, stone: Vector2i) -> void:
	if not RespawnPoint.set_to(state, player.slot, instance_name, stone):
		return
	var entry: Dictionary = state.store(player.slot, ID)
	var listed: Variant = entry.get(ACTIVATED)
	var stones: Array = listed if listed is Array else []
	var this_one: Array = [instance_name, stone.x, stone.y]
	if not stones.has(this_one):
		stones.append(this_one)
	entry[ACTIVATED] = stones
	state.events.append(WaystoneActivated.new(player.id, player.slot, stone))
