class_name ChestFeature
extends Feature
## Treasure chests (#124): placed by hand in region pieces (`c`), opened by the first player who
## walks onto one. An opened chest bursts into loot and **every player in the instance gets their
## own
## roll** on the instance's loot table (owner, #124), not only the one who opened it. The rolls
## come from the feature's own random stream (#32), so a replay opens the same chests with the
## same loot; a ChestOpened event says who got what, and each player's loot goes into their own
## profile (#74). Loot on the ground (#203) is found the same way, by the first player to step on
## it, with every player rolling their own; a LootFound event says so, as it's no chest.

## How many times each player rolls on the table when a chest opens.
const ROLLS_PER_PLAYER: int = 1

## The instance's loot table (#90), which the chests roll on.
var table: LootTable
## Every chest still closed, in the region's order.
var chests: Array[Vector2i] = []
## Every loot spot still lying on the ground, in the region's order.
var loot_spots: Array[Vector2i] = []
var _rng: Rng


func _init(instance_table: LootTable) -> void:
	table = instance_table


func id() -> int:
	return Features.CHESTS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func start(state: GameState) -> void:
	chests = state.region.chests.duplicate()
	loot_spots = state.region.loot_spots.duplicate()
	_rng = Rng.new(state.rng_seed, id())


func step(state: GameState, _commands: Array[Command]) -> void:
	# Copied, as opening adds events.
	for event: RefCounted in state.events.duplicate():
		var moved: EntityMoved = event as EntityMoved
		if moved == null or not (chests.has(moved.to) or loot_spots.has(moved.to)):
			continue
		var walker: Entity = state.entity(moved.entity_id)
		if walker == null or walker.slot == Entity.NO_SLOT:
			continue
		if chests.has(moved.to):
			chests.erase(moved.to)
			state.events.append(_open(state, moved.to, walker.id))
		else:
			loot_spots.erase(moved.to)
			state.events.append(_find(state, moved.to, walker.id))


func hash_values() -> Array[int]:
	var values: Array[int] = [chests.size()]
	for chest: Vector2i in chests:
		values.append(chest.x)
		values.append(chest.y)
	values.append(loot_spots.size())
	for spot: Vector2i in loot_spots:
		values.append_array([spot.x, spot.y])
	values.append_array(_rng.hash_values())
	return values


## The chests still closed and the loot still lying, in their order, and the stream's state.
func save_values() -> Dictionary:
	return {
		"chests": DataReader.flat(chests),
		"loot": DataReader.flat(loot_spots),
		"rng": _rng.hash_values(),
	}


func load_values(state: GameState, values: DataReader) -> void:
	var closed: Array[Vector2i] = values.tiles("chests", state.region)
	for chest: Vector2i in closed:
		if not state.region.chests.has(chest) or closed.count(chest) > 1:
			values.fail("a saved chest on %s isn't one of the region's" % chest)
			return
	chests = closed
	var lying: Array[Vector2i] = values.tiles("loot", state.region)
	for spot: Vector2i in lying:
		if not state.region.loot_spots.has(spot) or lying.count(spot) > 1:
			values.fail("saved loot on %s isn't the region's" % spot)
			return
	loot_spots = lying
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	if restored == null:
		values.fail("the chests' random stream isn't four 32-bit words, not all zero")
		return
	_rng = restored


## Opens the chest on `tile` for the player `opener_id`: every player's loot from it, as the event.
func _open(state: GameState, tile: Vector2i, opener_id: int) -> ChestOpened:
	return ChestOpened.new(tile, opener_id, _roll_for_players(state))


## Finds the loot on `tile` for the player `finder_id`: every player's roll from it, as the event.
func _find(state: GameState, tile: Vector2i, finder_id: int) -> LootFound:
	return LootFound.new(tile, finder_id, _roll_for_players(state))


## Every player's loot from one chest, by slot, in slot order so the stream rolls the same way.
func _roll_for_players(state: GameState) -> Dictionary[int, Dictionary]:
	var loot: Dictionary[int, Dictionary] = {}
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) == null:
			continue
		var found: Dictionary[String, int] = {}
		for _roll: int in ROLLS_PER_PLAYER:
			var drawn: Dictionary[String, int] = table.roll(_rng, table)
			for item: String in drawn:
				var had: int = found.get(item, 0)
				found[item] = had + drawn[item]
		loot[slot] = found
	return loot
