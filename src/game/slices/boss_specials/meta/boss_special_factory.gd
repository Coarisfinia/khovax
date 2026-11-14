class_name BossSpecialFactory
extends RefCounted
## Builds an instance's boss specials feature (#2410, #823) with every species' special, from the
## ability data; a species whose special doesn't load has none.


static func build(_setup: FeatureSetup) -> BossSpecialFeature:
	return BossSpecialFeature.new(SpeciesContent.cached().specials())
