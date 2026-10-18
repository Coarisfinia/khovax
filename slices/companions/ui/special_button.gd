class_name SpecialButton
extends ActionButton
## The special attack's touch button (#431): fires this machine's player's companion's special
## (`special_attack`, #410), as the E key does. It shows a burst for the special and, while it cools
## down, a circle with the seconds left; it never vanishes (#429), and it's drawn faded while the
## special can't fire: cooling down, or no wild monster next to the companion to strike.

@export var driver: GameDriver


func _init() -> void:
	action = &"special_attack"
	column_index = 1


func corner_text() -> String:
	var left: int = _cooldown_left()
	if left <= 0:
		return ""
	return str(ceili(float(left) / Simulation.TICKS_PER_SECOND))


func cooldown_share() -> float:
	var special: SpecialAttackFeature = _special()
	var companions: CompanionFeature = _companions()
	if special == null or companions == null:
		return 0.0
	var companion_id: int = companions.companion_of(_slot())
	if companion_id == 0:
		return 0.0
	var full: int = special.cooldowns.get(companions.species_of(companion_id), 0)
	return float(_cooldown_left()) / full if full > 0 else 0.0


func usable() -> bool:
	var companions: CompanionFeature = _companions()
	var wild: WildMonsterFeature = _feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var special: SpecialAttackFeature = _special()
	if special == null or not special.enabled or companions == null or wild == null:
		return false
	if _cooldown_left() > 0:
		return false
	var companion_id: int = companions.companion_of(_slot())
	if companion_id == 0:
		return false
	var tile: Vector2i = driver.state.entity(companion_id).tile
	return CompanionAttackFeature.target_next_to(driver.state, wild, tile) != 0


## A burst: eight rays around a dot.
func _draw_icon(area: Rect2, ink: Color) -> void:
	var middle: Vector2 = area.get_center()
	var inner: float = area.size.x * 0.1
	var outer: float = area.size.x * 0.3
	for ray: int in 8:
		var way: Vector2 = Vector2.RIGHT.rotated(TAU * ray / 8.0)
		draw_line(middle + way * inner, middle + way * outer, ink, INK_PIXELS)
	draw_circle(middle, inner * 0.7, ink)


func _cooldown_left() -> int:
	var special: SpecialAttackFeature = _special()
	return special.cooldown_left(_slot()) if special != null else 0


func _special() -> SpecialAttackFeature:
	return _feature(Features.SPECIALS) as SpecialAttackFeature


func _companions() -> CompanionFeature:
	return _feature(Features.COMPANIONS) as CompanionFeature


func _feature(feature_id: int) -> Feature:
	if driver == null or driver.state == null:
		return null
	return driver.state.feature(feature_id)


func _slot() -> int:
	return driver.input.slot if driver != null and driver.input != null else 0
