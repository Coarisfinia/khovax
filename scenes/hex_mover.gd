class_name HexMover
extends Node
## Moves a HexPiece tile by tile from the movement actions (move_up, move_down, move_left,
## move_right), so keyboard, touch and controller all feed the same input. The piece's tile is the
## truth and changes at once, in whole steps; only its drawn position glides there, at a constant
## speed, so steps in a row read as one smooth walk. It never leaves the grid.

## Time to walk from one tile to the next.
const STEP_SECONDS: float = 0.3

@export var piece: HexPiece
@export var grid: HexGrid

## How far the current step is, from 0 (just left) to 1 (arrived).
var _progress: float = 1.0
var _from: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	advance(delta, input)


## Moves by one time step with the given input. Called every frame; tests call it with fixed steps.
func advance(delta: float, input: Vector2) -> void:
	if piece == null or grid == null:
		return
	# Time is spent in steps. Time left over when a step ends goes into the next one, and the next
	# step starts at once, so a held direction walks at a constant speed even when frames stutter.
	var time: float = delta / STEP_SECONDS
	if _progress >= 1.0:
		_start_step(input)
	while _progress < 1.0 and time > 0.0:
		var used: float = minf(time, 1.0 - _progress)
		_progress += used
		time -= used
		piece.position = _from.lerp(piece.tile_position(), _progress)
		if _progress >= 1.0:
			_start_step(input)


func is_moving() -> bool:
	return _progress < 1.0


## Starts a step toward the input's direction, unless there is no input or it would leave the grid.
func _start_step(input: Vector2) -> void:
	var next: Vector2i = piece.tile + Hex.direction_toward(input, piece.tile)
	if next == piece.tile or not grid.has_tile(next):
		return
	_from = piece.position
	_progress = 0.0
	piece.tile = next
	piece.position = _from
