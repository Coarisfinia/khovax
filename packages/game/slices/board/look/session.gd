class_name Session
extends Node
## What the slices see of the running session (#514): the world, the instance this machine's player
## is in, and its ticks. The driver (GameDriver) is one; the slices only ever name this class, so
## they never reach game/, which wires them together (packages/game-checks/import_rules.py).

## After every tick, with the tick's number and the events the features and the world raised in it,
## in order: how views learn about one-shot moments (a domination, a ring breaking) to play an
## effect. Every tick is announced exactly once, however many ticks a frame runs. `events` is the
## view's own copy, and the events themselves must only be read. They include those of an instance
## this machine's player just left: a view of the instance they're in takes `local_events`.
signal ticked(tick: int, events: Array[RefCounted])

## This machine's player's input (the controls' LocalInput, #851): its slot, and whether it's heard.
@export var input: SessionInput
## Holds this machine's player's profile, whose first carried monster is their companion (#338);
## none in tests that build a driver alone, whose players then bring none.
@export var holder: ProfileHolder

## The world: every instance it has loaded.
var world: World
## The commands the last tick ran on, one per slot (null for a slot that gave none), for views that
## show what a command decided, like the walk held at an exit (ExitHoldHint, #1010). Only to read.
var last_commands: Array[Command] = []
## The instance this machine's player is in now, which the views draw; null without a world.
var state: GameState:
	get:
		if world == null:
			return null
		return world.instances.get(local_instance_name())


## Announces a tick that ran, with its events (`ticked`).
func announce(tick: int, events: Array[RefCounted]) -> void:
	ticked.emit(tick, events)


## The events of `events` that the instance this machine's player is in raised (#932), as the
## event bus knows them: the driver also passes on those of an instance they just left, and every
## instance counts its entity ids from 1, so an id in one names another entity here.
func local_events(events: Array[RefCounted]) -> Array[RefCounted]:
	var local: Array[RefCounted] = []
	var shown: GameState = state
	if shown == null:
		return local
	for event: RefCounted in events:
		if shown.events.has(event):
			local.append(event)
	return local


## The blueprint name of the instance this machine's player is in; "" without a world.
func local_instance_name() -> String:
	return ""


## How far real time is into the next tick, from 0 to 1: views draw between ticks with it.
func tick_fraction() -> float:
	return 0.0


## How far `entity_id` in `instance` (an instance's state) is through its step, from 0 (on the
## tile it walks from) to 1 (arrived), by tick and by how far real time is into the next one: views
## glide walkers with it. 1 when it stands, or the instance has no movement.
func walk_progress(instance: GameState, entity_id: int) -> float:
	var movement: MovementFeature = instance.feature(MovementFeature.ID) as MovementFeature
	var walk: Walk = movement.walk(entity_id) if movement != null else null
	if walk == null or not walk.is_moving():
		return 1.0
	var ticks_done: float = MovementFeature.MOVE_TICKS - walk.ticks_left + tick_fraction()
	return clampf(ticks_done / MovementFeature.MOVE_TICKS, 0.0, 1.0)


## Holds the ticks while a menu is open (`on`), or lets them run again: real time stops reaching
## the session. The driver refines it for co-op.
func pause(on: bool) -> void:
	set_process(not on)
