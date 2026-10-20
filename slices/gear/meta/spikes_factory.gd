class_name SpikesFactory
extends RefCounted
## Builds an instance's spikes feature (#692, #823) with every spikes' damage, by the code of its
## gear id, from the gear's content data. Gear that doesn't load is an error, and no spikes hurt
## then.


static func build(_setup: FeatureSetup) -> SpikesFeature:
	var content: GearContent = GearContent.load_gear()
	if not content.problem.is_empty():
		push_error("the gear doesn't load: " + content.problem)
	var damages: Dictionary[int, int] = {}
	for item: GearItem in content.items.values():
		if item.damage > 0:
			damages[SpikesFeature.code_of(item.id)] = item.damage
	return SpikesFeature.new(damages)
