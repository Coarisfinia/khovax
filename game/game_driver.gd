class_name GameDriver
extends Node
## Runs the simulation at its fixed tick rate. Real time only decides when ticks happen, never what
## they do: each tick takes the local player's command (later also the network's or a replay's)
## and steps the state. It processes before everything else (process_priority in main.tscn), so
## the state is current when views draw.

## Ticks one frame may run; more real time than this is dropped.
const MAX_TICKS_PER_FRAME: int = 5

@export var grid_radius: int = 3
@export var start_tile: Vector2i = Vector2i(1, -1)
@export var input: LocalInput

var state: GameState
var _accumulated: float = 0.0


func _ready() -> void:
	state = GameState.new(grid_radius, start_tile, 0)


func _process(delta: float) -> void:
	advance(delta)


## Runs as many whole ticks as `delta` adds up to, at most MAX_TICKS_PER_FRAME. Called every
## frame; tests call it with fixed steps.
func advance(delta: float) -> void:
	_accumulated += delta
	var tick_seconds: float = 1.0 / Simulation.TICKS_PER_SECOND
	var ticks: int = 0
	while _accumulated >= tick_seconds and ticks < MAX_TICKS_PER_FRAME:
		_accumulated -= tick_seconds
		ticks += 1
		var commands: Array[Command] = [input.command(state)]
		Simulation.step(state, commands)
	# After a long frame (a hitch, a backgrounded tab), the rest of the time is dropped rather than
	# caught up, which would freeze the game in a growing backlog. It only shifts when ticks run;
	# what they do still depends on the commands alone.
	_accumulated = minf(_accumulated, tick_seconds)


## How far real time is into the next tick, from 0 to 1: views draw between ticks with it.
func tick_fraction() -> float:
	return clampf(_accumulated * Simulation.TICKS_PER_SECOND, 0.0, 1.0)
