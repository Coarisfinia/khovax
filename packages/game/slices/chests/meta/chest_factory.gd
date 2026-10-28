class_name ChestFactory
extends RefCounted
## Builds an instance's treasure chests (#124, #694, #823), rolling on its chest loot table, with
## the loot on its ground rolling on its instance loot table. Either not loading is an error, and
## the instance has no chests then, except a chest table for an instance without one whose chests
## all hold their own item (ChestPlacements.held, #1592).


static func build(setup: FeatureSetup) -> ChestFeature:
	var chest_table: LootTable = LootContent.table_for(setup.chest_table, LootTable.CHEST)
	var ground_table: LootTable = LootContent.instance_table_for(setup)
	var table_needed: bool = not setup.chest_table.is_empty() or _rolls(setup.region)
	if (chest_table == null and table_needed) or ground_table == null:
		push_error("instance %s's chest or instance loot table doesn't load" % setup.instance)
		return null
	return ChestFeature.new(chest_table, ground_table)


## Whether a chest `region` places rolls on a chest table, rather than holding its own item.
static func _rolls(region: Region) -> bool:
	var placed: Dictionary[Vector2i, String] = region.placed(ChestPlacements.CHEST)
	for chest: Vector2i in placed:
		if ChestPlacements.held(placed[chest]).is_empty():
			return true
	return false
