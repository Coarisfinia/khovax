class_name TotemButton
extends ActionButton
## The totem's touch button (#429): places this machine's player's totem (`place_totem`, #423), as
## the T key does. It shows the totem's icon and its charges left, 0 when it has none, and is drawn
## faded while no rule would take the totem there: out of charges, or on neither a ring waiting for
## a totem, theirs or an ally's (DominationFeature.can_place_totem), nor a ring around a control
## point it would take or ward (ControlPointFeature.can_place_totem, #1503). It lives in a slice
## after both, since the domination's slice comes before the control points'.

## The state, tick and player slot the button last asked the rules for, and their answer.
var _asked_state: GameState
var _asked_tick: int = -1
var _asked_slot: int = -1
var _answer: bool = false


func _init() -> void:
	icon = preload("res://assets/game-icons/totem.svg")
	action = &"place_totem"


func corner_text() -> String:
	var domination: DominationFeature = feature(DominationFeature.ID) as DominationFeature
	var placer: Entity = player()
	if domination == null or placer == null:
		return "0"
	return str(domination.totems.charges_of(placer.id))


## Asks the rules themselves (#931), so the button never disagrees with what a press does. The
## answer holds for a whole tick, since the state changes only in a tick: the control points'
## question may flood the region, and the button is drawn every frame.
func usable() -> bool:
	var game: GameState = state()
	if game == null:
		return false
	if game != _asked_state or game.tick != _asked_tick or slot() != _asked_slot:
		_asked_state = game
		_asked_tick = game.tick
		_asked_slot = slot()
		_answer = _ask(game)
	return _answer


func _ask(game: GameState) -> bool:
	var placer: Entity = player()
	if placer == null:
		return false
	var domination: DominationFeature = feature(DominationFeature.ID) as DominationFeature
	if domination != null and domination.can_place_totem(game, placer.id):
		return true
	var points: ControlPointFeature = feature(ControlPointFeature.ID) as ControlPointFeature
	return points != null and points.can_place_totem(game, placer.id)
