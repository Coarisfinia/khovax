class_name RegionFeatures
extends RefCounted
## The features an instance has because of what its region holds (#879), not because its blueprint
## lists them: what its region pieces' legends place, over all of its pieces. A slice that places
## something on the ground says through its PlacementReader which feature runs it; the core's own
## meanings (exits, wild monsters, hiding) and region pieces to enter are matched here. Only which
## features; FeatureFactories says when they step.


## Every slice's reader of what it places on a region's ground (#824).
static func readers() -> Array[PlacementReader]:
	var all: Array[PlacementReader] = [
		TriggerPlacements.new(),
		NpcPlacements.new(),
		WildSpotPlacements.new(),
		ChestPlacements.new(),
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
		needed.append(WildMonsterFeature.ID)
	if HidingFeature.has_hiding(region):
		needed.append(HidingFeature.ID)
	for reader: PlacementReader in readers():
		for kind: String in reader.kinds():
			if not region.placed(kind).is_empty() and not needed.has(reader.feature()):
				needed.append(reader.feature())
	return needed


## The features the core's own legend meanings and region pieces need.
static func _built_in() -> Array[String]:
	return [ExitFeature.ID, EnteringFeature.ID, WildMonsterFeature.ID, HidingFeature.ID]
