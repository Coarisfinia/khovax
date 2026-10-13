class_name GameDriver
extends Node
## Runs the simulation at its fixed tick rate. Real time only decides when ticks happen, never what
## they do: each tick takes the local player's command (later also the network's or a replay's)
## and steps the state. Put it first in the scene, so the state is current when views draw.

@export var grid_radius: int = 3
@export var start_tile: Vector2i = Vector2i(1, -1)
@export var input: LocalInput
## Shown at the simulation's grid size.
@export var grid: HexGrid

var state: GameState
var _accumulated: float = 0.0


func _ready() -> void:
	state = GameState.new(grid_radius, start_tile, 0)
	if grid != null:
		grid.radius = grid_radius


func _process(delta: float) -> void:
	advance(delta)


## Runs as many whole ticks as `delta` adds up to. Called every frame; tests call it with fixed
## steps.
func advance(delta: float) -> void:
	_accumulated += delta
	var tick_seconds: float = 1.0 / Simulation.TICKS_PER_SECOND
	while _accumulated >= tick_seconds:
		_accumulated -= tick_seconds
		var commands: Array[Command] = [input.command(state)]
		Simulation.step(state, commands)


## How far real time is into the next tick, from 0 to 1: views draw between ticks with it.
func tick_fraction() -> float:
	return clampf(_accumulated * Simulation.TICKS_PER_SECOND, 0.0, 1.0)
