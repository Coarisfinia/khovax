class_name SpeciesLootFeature
extends Feature
## What the features share that roll a table of a wild monster's species (#86): its loot table for
## a domination (DominationLootFeature), its harvest table for a felled one (HarvestFeature, #629,
## #687). Each holds its table of every species, the instance's table that a blank rolls on (#90),
## and its own random stream, which it hashes and saves; the subclass says when it rolls and for
## whom.

## Each species' table this feature rolls, by species id; a species without one drops nothing.
var tables: Dictionary[String, LootTable] = {}
## The instance's loot table, which a blank rolls on, or null for none.
var instance_table: LootTable
var _rng: Rng


func _init(
	species_tables: Dictionary[String, LootTable] = {},
	instance_loot: LootTable = null,
) -> void:
	tables = species_tables
	instance_table = instance_loot


func start(state: GameState) -> void:
	_rng = Rng.new(state.rng_seed, id())


## `times` rolls on `species`' table, added up as {item id: amount}; nothing for a species without
## one.
func roll_species(species: String, times: int) -> Dictionary[String, int]:
	var none: Dictionary[String, int] = {}
	return tables[species].roll_times(_rng, times, instance_table) if tables.has(species) else none


func hash_values() -> Array[int]:
	return _rng.hash_values()


## The stream's state; the tables follow from the blueprint and the content.
func save_values() -> Dictionary:
	return { "rng": _rng.hash_values() }


func load_values(_state: GameState, values: DataReader) -> void:
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	if restored == null:
		values.fail("feature %d's loot stream isn't four 32-bit words, not all zero" % id())
		return
	_rng = restored
