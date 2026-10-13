class_name GameDriver
extends Node
## Runs the simulation at its fixed tick rate. Real time only decides when ticks happen, never what
## they do: each tick takes the local player's command (later also the network's or a replay's)
## and steps the state. It processes before everything else (process_priority in main.tscn), so
## the state is current when views draw.

## After every tick, with the tick's number and the events the features raised in it, in order:
## how views learn about one-shot moments (a catch, a ring breaking) to play an effect. Every tick
## is announced exactly once, however many ticks a frame runs. `events` is the view's own copy,
## and the events themselves must only be read.
signal ticked(tick: int, events: Array[RefCounted])

## Ticks one frame may run; more real time than this is dropped.
const MAX_TICKS_PER_FRAME: int = 5

## The instance to run, by name from Instances.
@export var instance: String = Instances.BASIC
@export var input: LocalInput

var state: GameState
## Every tick of this run so far, to play back (#35).
var recording: Replay
var _accumulated: float = 0.0


func _ready() -> void:
	# Null for an unknown or invalid instance, which Instances.create reports; nothing runs then.
	state = Instances.create(instance, 0)
	if state != null:
		recording = Replay.new(instance, 0, 1)
		recording.begin(state)


func _process(delta: float) -> void:
	advance(delta)


## Runs as many whole ticks as `delta` adds up to, at most MAX_TICKS_PER_FRAME. Called every
## frame; tests call it with fixed steps.
func advance(delta: float) -> void:
	if state == null:
		return
	_accumulated += delta
	var tick_seconds: float = 1.0 / Simulation.TICKS_PER_SECOND
	var ticks: int = 0
	while _accumulated >= tick_seconds and ticks < MAX_TICKS_PER_FRAME:
		_accumulated -= tick_seconds
		ticks += 1
		# Indexed by slot; the other slots stay empty until co-op brings their commands.
		var commands: Array[Command] = []
		for _slot: int in input.slot:
			commands.append(null)
		commands.append(input.command(state))
		Simulation.step(state, commands)
		recording.record(state, commands)
		# A copy: the simulation clears its list when the next tick starts.
		var events: Array[RefCounted] = []
		events.assign(state.events)
		ticked.emit(state.tick, events)
	# After a long frame (a hitch, a backgrounded tab), the rest of the time is dropped rather than
	# caught up, which would freeze the game in a growing backlog. It only shifts when ticks run;
	# what they do still depends on the commands alone.
	_accumulated = minf(_accumulated, tick_seconds)


## How far real time is into the next tick, from 0 to 1: views draw between ticks with it.
func tick_fraction() -> float:
	return clampf(_accumulated * Simulation.TICKS_PER_SECOND, 0.0, 1.0)
