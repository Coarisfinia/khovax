class_name ChestFactory
extends RefCounted
## Builds an instance's treasure chests (#124, #694, #823), rolling on its chest loot table, with
## the
## loot on its ground rolling on its instance loot table. Either not loading is an error, and the
## instance has no chests then.


static func build(setup: FeatureSetup) -> ChestFeature:
	var chest_table: LootTable = LootContent.table_for(setup, setup.chest_table, LootTable.CHEST)
	var ground_table: LootTable = LootContent.instance_table_for(setup)
	if chest_table == null or ground_table == null:
		push_error("instance %s's chest or instance loot table doesn't load" % setup.instance)
		return null
	return ChestFeature.new(chest_table, ground_table)
