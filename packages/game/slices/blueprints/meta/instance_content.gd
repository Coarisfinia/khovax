class_name InstanceContent
extends RefCounted
## What an instance loads from (#816), as the content cache's keys (ContentCatalog), each with the
## Callable reading it: every content kind, since any feature may read any of them, and the regions
## of its blueprint and its variants. The background fill (ContentFill) reads them ahead, so an
## instance loads without reading a file.


## Every content kind, by its key, each read through its own `cached`.
static func kinds() -> Dictionary[String, Callable]:
	return {
		TileContent.KEY: TileContent.cached,
		AbilityContent.DIR: AbilityContent.cached,
		SpeciesContent.KEY: SpeciesContent.cached,
		DevelopmentContent.DIR: DevelopmentContent.cached,
		LootContent.DIR: LootContent.cached,
		LootContent.HARVEST_DIR: LootContent.cached.bind(LootContent.HARVEST_DIR),
		MaterialContent.DIR: MaterialContent.cached,
		GearContent.DIR: GearContent.cached,
		RecipeContent.DIR: RecipeContent.cached,
		FactionContent.DIR: FactionContent.cached,
		PeopleContent.DIR: PeopleContent.cached,
		DialogContent.DIR: DialogContent.cached,
		QuestContent.KEY: QuestContent.cached,
		RuleSetContent.DIR: RuleSetContent.cached,
		BlueprintContent.DIR: BlueprintContent.cached,
	}


## Everything an instance of the blueprint `instance_name` loads from: every kind, and, once the
## blueprints are read (they name its variants), its regions.
static func of(instance_name: String) -> Dictionary[String, Callable]:
	var loads: Dictionary[String, Callable] = kinds()
	if ContentCatalog.has(BlueprintContent.DIR):
		loads.merge(regions(instance_name))
	return loads


## The regions of the blueprint `instance_name` and of its variants that this build has, by their
## keys.
static func regions(instance_name: String) -> Dictionary[String, Callable]:
	var loads: Dictionary[String, Callable] = {}
	var region_names: Array[String] = [instance_name]
	var named: Blueprint = InstanceBlueprints.blueprint(instance_name)
	if named != null:
		for chosen_by: PackedStringArray in named.variants:
			if not chosen_by[1].is_empty():
				region_names.append(chosen_by[1])
	# A region this build leaves out (a test-only one) can't be read, so nothing waits for it.
	for region_name: String in region_names:
		if RegionFiles.exists(region_name):
			loads[RegionFiles.key(region_name)] = RegionFiles.cached.bind(region_name)
	return loads


## Starts reading everything in the background (ContentFill), as soon as the game has loaded (owner,
## on #816): every kind first, then the regions of the instance `start` and of those its realm
## draws beside it, then every other blueprint's, so the first walk through an exit finds its
## content read. Reads the realms here, on the calling thread, so the background never does.
static func prefetch(start: String) -> void:
	# The resource packs too, which the background reads regions and checks content through
	# (#1861): read lazily on two threads at once, they'd be read twice.
	var _packs: Array[ResourcePack] = ResourcePacks.loaded()
	var first: Array[String] = [start]
	var realm: Realm = Realms.holding(start)
	if realm != null:
		for side: int in Hex.DIRECTIONS.size():
			var beside: String = realm.beside(start, side)
			if not beside.is_empty() and not first.has(beside):
				first.append(beside)
	var _all_kept: bool = ContentFill.have(kinds())
	ContentFill.then(_prefetch_regions.bind(first))


## Asks the background fill for the regions of the blueprints `first`, then of every other one: it
## runs there, once the kinds before it are read.
static func _prefetch_regions(first: Array[String]) -> void:
	var loads: Dictionary[String, Callable] = {}
	var others: Array[String] = InstanceBlueprints.names()
	for instance_name: String in first + others:
		loads.merge(regions(instance_name))
	var _all_kept: bool = ContentFill.have(loads)
