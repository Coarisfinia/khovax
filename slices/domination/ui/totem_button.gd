class_name TotemButton
extends ActionButton
## The totem's touch button (#429): places this machine's player's totem on a ring waiting for one
## (`place_totem`, #423), as the T key does. It shows the totem's icon and its charges left, 0 when
## it has none, and is drawn faded while the player stands on no ring waiting for a totem.

@export var driver: Session


func _init() -> void:
	icon = preload("res://assets/game-icons/totem.svg")
	action = &"place_totem"


func corner_text() -> String:
	return str(_charges())


func usable() -> bool:
	var domination: DominationFeature = _domination()
	var player: Entity = _player()
	if domination == null or player == null or _charges() == 0:
		return false
	if not domination.encircled.has(player.id):
		return false
	return domination.ring_waiting(driver.state, player.id).has(player.tile)


func _charges() -> int:
	var domination: DominationFeature = _domination()
	var player: Entity = _player()
	return domination.totems.charges_of(player.id) if domination != null and player != null else 0


func _domination() -> DominationFeature:
	if driver == null or driver.state == null:
		return null
	return driver.state.feature(DominationFeature.ID) as DominationFeature


func _player() -> Entity:
	if driver == null or driver.state == null:
		return null
	var slot: int = driver.input.slot if driver.input != null else 0
	return driver.state.player(slot)
