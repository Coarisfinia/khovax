class_name RegionFeatures
extends RefCounted
## The features an instance has because of what its region holds (#879), not because its blueprint
## lists them: what its region pieces' legends place, over all of its pieces. A slice that places
## something on the ground says through its PlacementReader which feature runs it; the core's own
## meanings (exits, wild monsters, their schedules, packs, sleep, hunts and foraging, hiding,
## bosses' specials, #2410), tiles bare hands can harvest (#696) and region pieces to enter are
## matched here. Only which features; FeatureFactories says when they
## step.


## Every slice's reader of what it places on a region's ground (#824).
static func readers() -> Array[PlacementReader]:
	var all: Array[PlacementReader] = [
		TriggerPlacements.new(),
		NpcPlacements.new(),
		SealPlacements.new(),
		WildSpotPlacements.new(),
		ChestPlacements.new(),
		ControlPointPlacements.new(),
	]
	return all


## Whether the feature with this id comes from the region rather than from a blueprint's list.
static func implies(feature_id: String) -> bool:
	if _built_in().has(feature_id):
		return true
	for reader: PlacementReader in readers():
		if reader.feature() == feature_id:
			return true
	return false


## The ids of the features `region` needs for what it holds.
static func of(region: Region) -> Array[String]:
	var needed: Array[String] = []
	if not region.exits.is_empty():
		needed.append(ExitFeature.ID)
	if not region.piece_of.is_empty():
		needed.append(EnteringFeature.ID)
	if not region.wild_monsters.is_empty():
		# Every wild monster has its daily schedule (#1201), bands into packs by it (#1205), sleeps
		# by it (#1202), predators hunt by it (#1204), and grazers and drinkers feed by it (#1203).
		needed.append_array(
			[
				WildMonsterFeature.ID,
				ScheduleFeature.ID,
				PackFeature.ID,
				SleepFeature.ID,
				HuntFeature.ID,
				ForagingFeature.ID,
			],
		)
	if HidingFeature.has_hiding(region):
		needed.append(HidingFeature.ID)
	needed.append_array(_marked_wild_rules(region))
	if TileHarvestFeature.has_harvestable(region):
		needed.append(TileHarvestFeature.ID)
	if WaystoneFeature.has_waystone(region):
		needed.append(WaystoneFeature.ID)
	for reader: PlacementReader in readers():
		for kind: String in reader.kinds():
			if not region.placed(kind).is_empty() and not needed.has(reader.feature()):
				needed.append(reader.feature())
	return needed


## The features for what `region`'s legend marks its named wild monsters with: a boss fires its
## special (#2410), and one marked escaping escapes at its line (#2411).
static func _marked_wild_rules(region: Region) -> Array[String]:
	var needed: Array[String] = []
	if BossSpecialFeature.has_boss(region):
		needed.append(BossSpecialFeature.ID)
	if EscapeFeature.has_escaper(region):
		needed.append(EscapeFeature.ID)
	return needed


## The features the core's own legend meanings and region pieces need.
static func _built_in() -> Array[String]:
	return [
		ExitFeature.ID,
		EnteringFeature.ID,
		WildMonsterFeature.ID,
		ScheduleFeature.ID,
		PackFeature.ID,
		SleepFeature.ID,
		HuntFeature.ID,
		ForagingFeature.ID,
		HidingFeature.ID,
		BossSpecialFeature.ID,
		TileHarvestFeature.ID,
		WaystoneFeature.ID,
		EscapeFeature.ID,
	]
