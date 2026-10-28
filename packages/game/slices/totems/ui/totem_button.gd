class_name TotemButton
extends ActionButton
## The totem's touch button (#429): places this machine's player's totem (`place_totem`, #423), as
## the T key does. It shows the totem's icon and its charges left, 0 when it has none, and is drawn
## faded while no rule would take the totem there: out of charges, or on neither a ring waiting for
## a totem, theirs or an ally's (DominationFeature.can_place_totem), nor a ring around a control
## point it would take or ward (ControlPointFeature.can_place_totem, #1503). It lives in a slice
## after both, since the domination's slice comes before the control points'.


func _init() -> void:
	icon = preload("res://assets/game-icons/totem.svg")
	action = &"place_totem"


func corner_text() -> String:
	var domination: DominationFeature = feature(DominationFeature.ID) as DominationFeature
	var placer: Entity = player()
	if domination == null or placer == null:
		return "0"
	return str(domination.totems.charges_of(placer.id))


## Asks the rules themselves (#931), so the button never disagrees with what a press does.
func usable() -> bool:
	var placer: Entity = player()
	if placer == null:
		return false
	var domination: DominationFeature = feature(DominationFeature.ID) as DominationFeature
	if domination != null and domination.can_place_totem(state(), placer.id):
		return true
	var points: ControlPointFeature = feature(ControlPointFeature.ID) as ControlPointFeature
	return points != null and points.can_place_totem(state(), placer.id)
