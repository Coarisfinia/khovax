class_name WildMonsterFeature
extends Feature
## Wild monsters (#19): when the instance loads, one stands on every spot the region marks for it,
## as an entity no player controls, and each is of a species (#133). A spot whose region piece names
## its species gets that one (a boss arena pins its boss); every other spot rolls one from the
## blueprint's weighted list, from the feature's own random stream, so a replay places the same
## species. For now each just stands there (its look is a placeholder, #85); walkers can't step onto
## its tile (MovementFeature), and a later rule catches it (#20). Like every feature, switched off
## it keeps its state: the monsters stay where they are, and only its own rules stop.

## Every wild monster's entity id, in id order.
var monsters: Array[int] = []
## The blueprint's species ids for spots the region doesn't name, and how likely each one is.
var roster: Array[String] = []
var weights: Array[int] = []
## Each wild monster's species id, by entity id.
var _species: Dictionary[int, String] = {}
## Every species id this instance can place, sorted: the hash counts a species by its place here.
var _known: Array[String] = []


func _init(roster_ids: Array[String] = [], roster_weights: Array[int] = []) -> void:
	roster = roster_ids
	weights = roster_weights


func id() -> int:
	return Features.WILD_MONSTERS


func start(state: GameState) -> void:
	var rng: Rng = Rng.new(state.rng_seed, id())
	_known = roster.duplicate()
	for spot: Vector2i in state.region.wild_monsters:
		var species: String = state.region.named_species.get(spot, "")
		if species.is_empty() and not roster.is_empty():
			species = roster[rng.pick_weighted(weights)]
		if not _known.has(species):
			_known.append(species)
		# Can't be refused: an entity without a slot is always added.
		var monster: Entity = state.add_entity(Entity.NO_SLOT, spot)
		monsters.append(monster.id)
		_species[monster.id] = species
	_known.sort()


func entity_removed(_state: GameState, removed_id: int) -> void:
	monsters.erase(removed_id)
	var _dropped: bool = _species.erase(removed_id)


## Whether the entity with this id is a wild monster.
func is_wild_monster(entity_id: int) -> bool:
	return monsters.has(entity_id)


## The species id of the wild monster with this entity id, or "" when it has none.
func species_of(entity_id: int) -> String:
	return _species.get(entity_id, "")


## Each wild monster still in the instance as its entity's id and its species, in id order. The
## roster and the species this instance can place follow from the blueprint and the region.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for monster: int in monsters:
		saved.append({ "entity": monster, "species": _species[monster] })
	return { "wild_monsters": saved }


func load_values(state: GameState, values: DataReader) -> void:
	monsters.clear()
	_species.clear()
	for entry: DataReader in values.entries("wild_monsters"):
		var monster: int = entry.whole("entity", 1, DataReader.MOST)
		var species: String = entry.text("species")
		var standing: Entity = state.entity(monster)
		if standing == null or standing.slot != Entity.NO_SLOT or _species.has(monster):
			values.fail("wild monster %d isn't one entity without a player" % monster)
			return
		if not _known.has(species):
			values.fail("wild monster %d is of %s, which this instance doesn't place" % [
				monster,
				species,
			])
			return
		monsters.append(monster)
		_species[monster] = species
	monsters.sort()


func hash_values() -> Array[int]:
	var values: Array[int] = [monsters.size()]
	for monster: int in monsters:
		values.append(monster)
		values.append(_known.find(_species[monster]))
	return values
