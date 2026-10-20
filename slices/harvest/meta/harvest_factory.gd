class_name HarvestFactory
extends RefCounted
## Builds an instance's harvest of felled wild monsters (#629, #823) with every species' harvest
## table (#687) and the instance's own table for blanks, if it has one.


static func build(setup: FeatureSetup) -> HarvestFeature:
	var tables: Dictionary[String, LootTable] = LootContent.species_tables_for(
		LootContent.HARVEST_DIR,
		LootTable.HARVEST,
	)
	return HarvestFeature.new(tables, LootContent.instance_table_for(setup))
