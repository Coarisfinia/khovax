class_name DominationLootFeature
extends Feature
## Loot for a domination (#86): every player who did enough for the ring that dominated a wild
## monster gets rolls on its species' loot table, the dominator too; a blank rolls on the instance's
## table (#90), or gives nothing in an instance without one. What they did counts as points:
## WALL_POINTS for each tile of the ring's wall they colored, and one for every TICKS_PER_POINT
## ticks they stood on the wall while it sealed (#227). Every POINTS_PER_ROLL points is a roll, up
## to FULL_ROLLS, so a player who barely helped gets nothing (owner, #86). The numbers are
## placeholders, to tune.

const WALL_POINTS: int = 2
const TICKS_PER_POINT: int = Simulation.TICKS_PER_SECOND
const POINTS_PER_ROLL: int = 3
const FULL_ROLLS: int = 3

## Each species' loot table, by species id; a species without one drops nothing.
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


func id() -> int:
	return Features.DOMINATION_LOOT


func requires() -> Array[int]:
	var needed: Array[int] = [Features.DOMINATION]
	return needed


func start(state: GameState) -> void:
	_rng = Rng.new(state.rng_seed, id())


## Rolls every domination of this tick, in the order the dominations happened.
func step(state: GameState, _commands: Array[Command]) -> void:
	# Copied, as the loop adds DominationLoot events to the same list.
	for event: RefCounted in state.events.duplicate():
		var dominated: WildMonsterDominated = event as WildMonsterDominated
		if dominated == null or not tables.has(dominated.species):
			continue
		var loot: Dictionary[int, Dictionary] = {}
		for slot: int in GameState.MAX_PLAYERS:
			var rolls: int = rolls_for(dominated, slot)
			if rolls > 0:
				loot[slot] = tables[dominated.species].roll_times(_rng, rolls, instance_table)
		if not loot.is_empty():
			state.events.append(_rolled(dominated, loot))


## How many rolls the player in `slot` earned for the domination.
static func rolls_for(dominated: WildMonsterDominated, slot: int) -> int:
	var walls: int = dominated.walls_colored.get(slot, 0)
	var braced: int = dominated.braced_ticks.get(slot, 0)
	var points: int = walls * WALL_POINTS + Fixed.div_floor(braced, TICKS_PER_POINT)
	return mini(Fixed.div_floor(points, POINTS_PER_ROLL), FULL_ROLLS)


static func _rolled(
	dominated: WildMonsterDominated,
	loot: Dictionary[int, Dictionary],
) -> DominationLoot:
	return DominationLoot.new(dominated.monster_id, dominated.species, loot)


func hash_values() -> Array[int]:
	return _rng.hash_values()


## The stream's state; the tables follow from the blueprint and the content.
func save_values() -> Dictionary:
	return { "rng": _rng.hash_values() }


func load_values(_state: GameState, values: DataReader) -> void:
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	if restored == null:
		values.fail("the domination loot's random stream isn't four 32-bit words, not all zero")
		return
	_rng = restored
