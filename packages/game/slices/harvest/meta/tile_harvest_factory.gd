class_name TileHarvestFactory
extends RefCounted
## Builds an instance's harvesting of tiles by hand (#696, #823) with the tile table of every kind
## that can be harvested, named in its tile blueprint.


static func build(_setup: FeatureSetup) -> TileHarvestFeature:
	var tables: Dictionary[String, LootTable] = {}
	for kind: String in TileContent.cached().tiles:
		var yields: String = TileKinds.harvest_yields(kind)
		var table: LootTable = LootContent.table_for(yields, LootTable.TILE)
		if table != null:
			tables[kind] = table
	return TileHarvestFeature.new(tables)
