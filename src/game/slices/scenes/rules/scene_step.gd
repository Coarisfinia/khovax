class_name SceneStep
extends RefCounted
## One step of a deterministic scene (#2415): wait a number of ticks, move an actor to a tile at
## its pace, have an actor strike another (non-lethal unless specified), or emit an EventEmitted.

const WAIT: String = "wait"
const MOVE: String = "move"
const STRIKE: String = "strike"
const EMIT: String = "emit"

var kind: String = ""
var ticks: int = 0
var actor: String = ""
var target: String = ""
var to: Vector2i = Vector2i.ZERO
var pace: int = 0
var amount: int = 0
var lethal: bool = false
var event: String = ""


## A wait step that holds the scene for `wait_ticks` ticks.
static func make_wait(wait_ticks: int) -> SceneStep:
	var step: SceneStep = SceneStep.new()
	step.kind = WAIT
	step.ticks = wait_ticks
	return step


## A move step that walks `actor_id` to `goal` at `step_pace` ticks per tile (0 for its natural
## pace).
static func make_move(actor_id: String, goal: Vector2i, step_pace: int = 0) -> SceneStep:
	var step: SceneStep = SceneStep.new()
	step.kind = MOVE
	step.actor = actor_id
	step.to = goal
	step.pace = step_pace
	return step


## A strike step where `actor_id` deals `damage` to `target_id`, non-lethal unless `is_lethal`.
static func make_strike(
	actor_id: String,
	target_id: String,
	damage: int,
	is_lethal: bool = false,
) -> SceneStep:
	var step: SceneStep = SceneStep.new()
	step.kind = STRIKE
	step.actor = actor_id
	step.target = target_id
	step.amount = damage
	step.lethal = is_lethal
	return step


## An emit step that raises EventEmitted with `event_name`.
static func make_emit(event_name: String) -> SceneStep:
	var step: SceneStep = SceneStep.new()
	step.kind = EMIT
	step.event = event_name
	return step
