class_name FeatureFactories
extends RefCounted
## Every feature an instance blueprint can list (#823), by its id, with what builds it from the
## instance's FeatureSetup: a feature that reads content data from its slice's factory, one that
## reads nothing with new(). A feature whose region holds nothing for it (no exits, no triggers)
## builds as null and is left out. The order here is the step order every instance's features
## take, reviewed like code; each feature's `requires`, `after` and `before` are checked against
## it when an instance loads (GameState.order_problem).

static var _factories: Dictionary[String, Callable] = {}


## Whether a feature with this id can be listed.
static func has(feature_id: String) -> bool:
	return _all().has(feature_id)


## The listed features, built for `setup` in the step order; those built as null are left out.
static func build(listed: Array[String], setup: FeatureSetup) -> Array[Feature]:
	var features: Array[Feature] = []
	for feature_id: String in _all():
		if listed.has(feature_id):
			var feature: Feature = _all()[feature_id].call(setup)
			if feature != null:
				features.append(feature)
	return features


static func _all() -> Dictionary[String, Callable]:
	if _factories.is_empty():
		_factories = {
			MovementFeature.ID: _plain(MovementFeature),
			KnockdownFeature.ID: _plain(KnockdownFeature),
			TrailFeature.ID: _plain(TrailFeature),
			# Before the wild monsters and every feature that hurts or heals (#835).
			HealthFeature.ID: HealthFactory.build,
			WildMonsterFeature.ID: WildMonsterFactory.build,
			DominationFeature.ID: _plain(DominationFeature),
			# After domination, whose waiting rings it breaks, and before enrage, which enrages the
			# wild monsters of a ring that broke.
			WildAttackFeature.ID: _plain(WildAttackFeature),
			# After domination, whose rings' wild monsters it hurts (#692).
			SpikesFeature.ID: SpikesFactory.build,
			DominationLootFeature.ID: DominationLootFactory.build,
			EnrageFeature.ID: _plain(EnrageFeature),
			FogFeature.ID: _plain(FogFeature),
			# What the region holds: exits, triggers, region pieces to enter, wild monsters in
			# hiding, people to talk to.
			ExitFeature.ID: _exits,
			TriggerFeature.ID: _triggers,
			EnteringFeature.ID: _entering,
			HidingFeature.ID: _hiding,
			NpcFeature.ID: _npcs,
			ChestFeature.ID: ChestFactory.build,
			# The companions and the features built on them. A companion whose player walks out
			# through an exit goes with them whatever the order: the world moves it after the tick
			# (#716).
			CompanionFeature.ID: CompanionFactory.build,
			# After the companions, so a swap can't pick a monster that fainted (#597).
			CompanionSwapFeature.ID: _plain(CompanionSwapFeature),
			# After the companions too, whose fainted ones a revive item brings back (#656).
			ReviveItemFeature.ID: _plain(ReviveItemFeature),
			# The features that strike monsters: the type chart (#626), which doesn't step, the
			# companions' auto attacks, and the specials (#410).
			TypeEffectivenessFeature.ID: TypeChartFactory.build,
			CompanionAttackFeature.ID: _plain(CompanionAttackFeature),
			SpecialAttackFeature.ID: SpecialAttackFactory.build,
			# The harvest after the specials, whose strikes fell the wild monsters it drops
			# materials
			# for.
			HarvestFeature.ID: HarvestFactory.build,
			DialogFeature.ID: DialogFactory.build,
			TerritoryFeature.ID: TerritoryFactory.build,
		}
	return _factories


## What builds a feature that reads nothing: its class's new().
static func _plain(feature: GDScript) -> Callable:
	return func(_setup: FeatureSetup) -> Feature: return feature.new()


static func _exits(setup: FeatureSetup) -> ExitFeature:
	if setup.region.exits.is_empty():
		return null
	return ExitFeature.new()


static func _triggers(setup: FeatureSetup) -> TriggerFeature:
	if setup.region.placed(TriggerPlacements.KIND).is_empty():
		return null
	return TriggerFeature.new()


static func _entering(setup: FeatureSetup) -> EnteringFeature:
	if setup.region.piece_of.is_empty():
		return null
	return EnteringFeature.new()


static func _hiding(setup: FeatureSetup) -> HidingFeature:
	if not HidingFeature.has_hiding(setup.region):
		return null
	return HidingFeature.new()


static func _npcs(setup: FeatureSetup) -> NpcFeature:
	if setup.region.placed(NpcPlacements.KIND).is_empty():
		return null
	return NpcFeature.new()
