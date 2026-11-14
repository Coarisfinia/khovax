class_name TonicEffect
extends RefCounted
## One tonic's or draught's effect over time on its target (#2311, TonicEffectsFeature): which one,
## how strong, how long it still lasts and how long until it starts.

## Which effect it is (TonicEffectsFeature.KINDS), or a Slow-release Mend still waiting to land
## (TonicEffectsFeature.MEND).
var kind: String = ""
## Its strength in thousandths (Fixed): a Regrowth's share of full HP each second, a Ward's guard,
## a Quicken's share off the wait between strikes, a Fortify's share more damage, a Mend's share of
## full HP.
var strength: int = 0
## The ticks it still works, this one included once it has started.
var ticks: int = 0
## The ticks still to pass before it starts: at least the rest of the tick it was drunk on.
var waits: int = 0


func _init(
	effect_kind: String = "",
	effect_strength: int = 0,
	effect_ticks: int = 0,
	effect_waits: int = 0,
) -> void:
	kind = effect_kind
	strength = effect_strength
	ticks = effect_ticks
	waits = effect_waits
