class_name Instances
extends RefCounted
## Instance definitions: a map, a start and the features an instance has, in their step order. An
## instance switches game rules on and off by listing them, and they can change during a run.

const BASIC: String = "basic"


## A new state for the named instance, or null (with an error) for an unknown name or an invalid
## feature order.
static func create(instance_name: String, seed_value: int) -> GameState:
	var state: GameState = basic(seed_value) if instance_name == BASIC else null
	if state == null:
		push_error("unknown instance: " + instance_name)
		return null
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	return state


## The current playground: a disc of radius 3, walking, and a trail.
static func basic(seed_value: int) -> GameState:
	var ordered: Array[Feature] = [MovementFeature.new(), TrailFeature.new()]
	return GameState.new(3, Vector2i(1, -1), seed_value, ordered)
