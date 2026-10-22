class_name DominationLootFactory
extends RefCounted
## Builds an instance's domination loot feature (#86, #823) with every species' loot table and the
## instance's own table for blanks, if it has one.


static func build(setup: FeatureSetup) -> DominationLootFeature:
	var tables: Dictionary[String, LootTable] = LootContent.species_tables_for(
		LootContent.DIR,
		LootTable.SPECIES,
	)
	return DominationLootFeature.new(tables, LootContent.instance_table_for(setup))
