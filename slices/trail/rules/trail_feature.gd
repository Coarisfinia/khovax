class_name TrailFeature
extends Feature
## The trail (#87): the allies share one, every tile any player has stood on or moved onto, each
## remembering who colored it first (all players in an instance are allies, owner, #87). Rings are
## drawn with it, so allies close rings together. It grows from EntityMoved events, so the trail
## comes after movement in an instance's order. Walking over the trail again changes nothing; a
## domination clears only the ring that made it (DominationFeature, through `clear`).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "trail"

## The allies' trail.
var shared: Trail = Trail.new()


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	# Copied, as the loop adds TrailGrew events to the same list.
	for event: RefCounted in state.events.duplicate():
		var moved: EntityMoved = event as EntityMoved
		if moved == null or not _is_player(state, moved.entity_id):
			continue
		if shared.color(moved.to, moved.entity_id):
			state.events.append(_grew(moved))


## A player arriving colors the tile they stand on, if nobody has yet.
func entity_added(_state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		var _colored: bool = shared.color(added.tile, added.id)


## The event for a trail that grew by the tile `moved` walked onto.
static func _grew(moved: EntityMoved) -> TrailGrew:
	return TrailGrew.new(moved.entity_id, moved.from, moved.to)


static func _is_player(state: GameState, entity_id: int) -> bool:
	var entity: Entity = state.entity(entity_id)
	return entity != null and entity.slot != Entity.NO_SLOT


## Takes `tiles` off the trail (a ring that dominated or broke, #87): the trail leading up to it
## stays, and every player then colors the tile they stand on, so each starts a fresh trail where
## they are.
func clear(state: GameState, tiles: Array[Vector2i]) -> void:
	for tile: Vector2i in tiles:
		var _dropped: bool = shared.tiles.erase(tile)
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT:
			var _colored: bool = shared.color(entity.tile, entity.id)


## The trail as its tiles, sorted, and who colored each, in the same order.
func save_values() -> Dictionary:
	var tiles: Array[Vector2i] = shared.sorted_tiles()
	var colored_by: Array[int] = []
	for tile: Vector2i in tiles:
		colored_by.append(shared.tiles[tile])
	return { "tiles": DataReader.flat(tiles), "colored_by": colored_by }


## Who colored a tile may since have left the instance, so any entity id is taken.
func load_values(state: GameState, values: DataReader) -> void:
	var tiles: Array[Vector2i] = values.tiles("tiles", state.region)
	var colored_by: Array[int] = values.wholes("colored_by", 1, DataReader.MOST)
	shared = Trail.new()
	if colored_by.size() != tiles.size():
		values.fail("the trail's tiles and who colored them don't match")
		return
	for i: int in tiles.size():
		if not shared.color(tiles[i], colored_by[i]):
			values.fail("the trail has %s twice" % tiles[i])
			return


func hash_values() -> Array[int]:
	var tiles: Array[Vector2i] = shared.sorted_tiles()
	var values: Array[int] = [tiles.size()]
	for tile: Vector2i in tiles:
		values.append_array([tile.x, tile.y, shared.tiles[tile]])
	return values
