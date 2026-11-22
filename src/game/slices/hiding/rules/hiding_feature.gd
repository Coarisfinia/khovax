class_name HidingFeature
extends Feature
## Hiding tiles (#202): a wild monster that starts on a tile whose kind hides (a tile blueprint's
## `hides` trait, e.g. shrubs) stays hidden there until a player comes next to it, then jumps out
## (a MonsterJumpedOut event) and is a wild monster like any other from then on. Hidden, it still
## blocks walkers, and a ring around it still dominates it: hiding only keeps it out of sight. It
## stays in its tile while hidden, held there (WildMonsterFeature.hold), even where no ring could
## enclose it (#364).
## Instances whose region has such a monster have it.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "hiding"
## How near a player comes before a hidden wild monster jumps out: next to it.
const NEAR: int = 1

## Every hidden wild monster's entity id, in id order.
var hidden: Array[int] = []
## The hidden wild monsters that stay out of sight without jumping out when a player nears (#2416,
## ShyWatcherFeature), in id order.
var quiet: Array[int] = []


func id() -> String:
	return ID


## The wild monsters it hides, which an instance without wild monster spots lacks (#884): nothing
## hides there, so nothing is held or jumps out.
func after() -> Array[String]:
	var earlier: Array[String] = [WildMonsterFeature.ID]
	return earlier


## Hides every wild monster that starts on a tile that hides.
func start(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return
	for monster: int in wild.monsters:
		if hides_at(state.region, state.entity(monster).tile):
			hidden.append(monster)
			wild.hold(monster, true)


func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return
	var still: Array[int] = []
	for monster: int in hidden:
		var tile: Vector2i = state.entity(monster).tile
		if not quiet.has(monster) and _player_near(state, tile):
			state.events.append(_jumped_out(monster, tile))
			wild.hold(monster, false)
		else:
			still.append(monster)
	hidden = still


func entity_removed(_state: GameState, removed_id: int) -> void:
	hidden.erase(removed_id)
	quiet.erase(removed_id)


## Hides the wild monster `entity_id` out of sight; when `no_jump` is true (#2416), it stays hidden
## without jumping out when a player nears.
func hide(entity_id: int, no_jump: bool = false) -> void:
	if not hidden.has(entity_id):
		hidden.append(entity_id)
		hidden.sort()
	if no_jump and not quiet.has(entity_id):
		quiet.append(entity_id)
		quiet.sort()


## Reveals `entity_id` without jumping out or changing whether another rule holds it.
func unhide(entity_id: int) -> void:
	hidden.erase(entity_id)
	quiet.erase(entity_id)


## Whether the wild monster with this entity id is hidden.
func is_hidden(entity_id: int) -> bool:
	return hidden.has(entity_id)


## Brings the hidden wild monster `entity_id` out of hiding at once (a scene moving it, #2415).
func reveal(state: GameState, entity_id: int) -> void:
	if not hidden.has(entity_id):
		return
	hidden.erase(entity_id)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild != null:
		wild.hold(entity_id, false)
	var standing: Entity = state.entity(entity_id)
	if standing != null:
		state.events.append(_jumped_out(entity_id, standing.tile))


## The hidden wild monsters are out of sight (GameState.concealed), so their views needn't know
## this slice.
func conceals(entity_id: int) -> bool:
	return is_hidden(entity_id)


## Whether a wild monster on `tile` of `region` hides there.
static func hides_at(region: Region, tile: Vector2i) -> bool:
	var kind: String = region.terrain.get(tile, Region.GROUND)
	return TileKinds.hides(kind)


## Whether any wild monster spot of `region` hides, so its instance needs the feature.
static func has_hiding(region: Region) -> bool:
	for spot: Vector2i in region.wild_monsters:
		if hides_at(region, spot):
			return true
	return false


func hash_values() -> Array[int]:
	var values: Array[int] = [hidden.size()]
	values.append_array(hidden)
	# Only mix quiet ids when present so instances without quiet hiders keep their hash (#876).
	if not quiet.is_empty():
		values.append(quiet.size())
		values.append_array(quiet)
	return values


## The wild monsters still hidden, by entity id, and the quiet ones when any are.
func save_values() -> Dictionary:
	var saved: Dictionary = { "hidden": hidden }
	if not quiet.is_empty():
		saved["quiet"] = quiet
	return saved


func load_values(state: GameState, values: DataReader) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var saved: Array[int] = values.wholes("hidden", 1, DataReader.MOST)
	hidden.clear()
	quiet.clear()
	for monster: int in saved:
		if wild == null or not wild.monsters.has(monster) or hidden.has(monster):
			values.fail("hidden %d isn't one wild monster" % monster)
			return
		hidden.append(monster)
		wild.hold(monster, true)
	hidden.sort()
	if (values.data as Dictionary).has("quiet"):
		var saved_quiet: Array[int] = values.wholes("quiet", 1, DataReader.MOST)
		for monster: int in saved_quiet:
			if not hidden.has(monster) or quiet.has(monster):
				values.fail("quiet %d isn't one hidden wild monster" % monster)
				return
			quiet.append(monster)
		quiet.sort()


static func _jumped_out(monster: int, tile: Vector2i) -> MonsterJumpedOut:
	return MonsterJumpedOut.new(monster, tile)


static func _player_near(state: GameState, tile: Vector2i) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null and Hex.distance(player.tile, tile) <= NEAR:
			return true
	return false
