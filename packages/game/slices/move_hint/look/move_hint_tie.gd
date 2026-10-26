class_name MoveHintTie
extends Node
## Ties the move hint's first walk (#1222) to the running session: once this machine's player starts
## a step, the keeper notes in their profile that they walked, and the hint (MoveHint) fades. This
## only watches the session.

## The session, whose ticks tell when the player steps.
@export var driver: Session
## Where the walk is kept.
@export var keeper: MoveHintKeeper


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


## A step of this machine's player in the instance they're in is their walk.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	if keeper.walked or driver.state == null or driver.input == null:
		return
	var player: Entity = driver.state.player(driver.input.slot)
	if player == null:
		return
	for event: RefCounted in driver.local_events(events):
		var moved: EntityMoved = event as EntityMoved
		if moved != null and moved.entity_id == player.id:
			keeper.walk()
			return
