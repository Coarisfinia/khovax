class_name SpecialButton
extends ActionButton
## The special attack's touch button (#431): fires this machine's player's companion's special
## (`special_attack`, #410), as the E key and a controller's right trigger (#779) do. It shows an
## explosion icon for the special and, while it cools down, a circle with the seconds left; it never
## vanishes (#429), and it's drawn faded while the special can't fire
## (SpecialAttackFeature.can_fire): cooling down, no companion whose species has a special, or no
## wild monster next to it to strike.


func _init() -> void:
	icon = ResourcePacks.texture("icon_spiky_explosion")
	action = &"special_attack"
	column_index = 1


func corner_text() -> String:
	var left: int = _cooldown_left()
	if left <= 0:
		return ""
	return str(ceili(float(left) / Simulation.TICKS_PER_SECOND))


func cooldown_share() -> float:
	var special: SpecialAttackFeature = _special()
	var companions: CompanionFeature = feature(CompanionFeature.ID) as CompanionFeature
	if special == null or companions == null:
		return 0.0
	var companion_id: int = companions.companion_of(slot())
	if companion_id == 0:
		return 0.0
	var full: int = special.cooldowns.get(companions.species_of(companion_id), 0)
	return float(_cooldown_left()) / full if full > 0 else 0.0


## Asks the rule itself (#931), so the button never disagrees with what a press does.
func usable() -> bool:
	var special: SpecialAttackFeature = _special()
	return special != null and special.can_fire(state(), slot())


func _cooldown_left() -> int:
	var special: SpecialAttackFeature = _special()
	return special.cooldown_left(slot()) if special != null else 0


func _special() -> SpecialAttackFeature:
	return feature(SpecialAttackFeature.ID) as SpecialAttackFeature
