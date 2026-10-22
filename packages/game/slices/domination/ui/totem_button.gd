class_name TotemButton
extends ActionButton
## The totem's touch button (#429): places this machine's player's totem on a ring waiting for one
## (`place_totem`, #423), as the T key does. It shows the totem's icon and its charges left, 0 when
## it has none, and is drawn faded while the player can't place it
## (DominationFeature.can_place_totem): out of charges, or on no ring waiting for a totem, theirs or
## an ally's.


func _init() -> void:
	icon = preload("res://assets/game-icons/totem.svg")
	action = &"place_totem"


func corner_text() -> String:
	var domination: DominationFeature = _domination()
	var placer: Entity = player()
	if domination == null or placer == null:
		return "0"
	return str(domination.totems.charges_of(placer.id))


## Asks the rule itself (#931), so the button never disagrees with what a press does.
func usable() -> bool:
	var domination: DominationFeature = _domination()
	var placer: Entity = player()
	return domination != null and placer != null and domination.can_place_totem(state(), placer.id)


func _domination() -> DominationFeature:
	return feature(DominationFeature.ID) as DominationFeature
