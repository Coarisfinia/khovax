class_name TotemButton
extends ActionButton
## The totem's touch button (#429): places this machine's player's totem on a ring waiting for one
## (`place_totem`, #423), as the T key does. It shows the totem's icon and its charges left, 0 when
## it has none, and is drawn faded while the player stands on no ring waiting for a totem.

@export var driver: GameDriver


func _init() -> void:
	action = &"place_totem"


func corner_text() -> String:
	return str(_charges())


func usable() -> bool:
	var domination: DominationFeature = _domination()
	var player: Entity = _player()
	if domination == null or player == null or _charges() == 0:
		return false
	return domination.ring_waiting(driver.state, player.id).has(player.tile)


## A totem: a pole standing on a foot, with a diamond on top.
func _draw_icon(area: Rect2, ink: Color) -> void:
	var middle: Vector2 = area.get_center()
	var high: float = area.size.y * 0.3
	draw_line(
		middle + Vector2(0.0, -high * 0.4),
		middle + Vector2(0.0, high),
		ink,
		INK_PIXELS * 2.0,
	)
	var foot: float = area.size.x * 0.16
	draw_line(middle + Vector2(-foot, high), middle + Vector2(foot, high), ink, INK_PIXELS * 2.0)
	var top: Vector2 = middle + Vector2(0.0, -high * 0.75)
	var corner: float = area.size.x * 0.12
	var diamond: PackedVector2Array = [
		top + Vector2(0.0, -corner),
		top + Vector2(corner, 0.0),
		top + Vector2(0.0, corner),
		top + Vector2(-corner, 0.0),
	]
	draw_colored_polygon(diamond, ink)


func _charges() -> int:
	var domination: DominationFeature = _domination()
	var player: Entity = _player()
	return domination.totems.charges_of(player.id) if domination != null and player != null else 0


func _domination() -> DominationFeature:
	if driver == null or driver.state == null:
		return null
	return driver.state.feature(Features.DOMINATION) as DominationFeature


func _player() -> Entity:
	if driver == null or driver.state == null:
		return null
	var slot: int = driver.input.slot if driver.input != null else 0
	return driver.state.player(slot)
