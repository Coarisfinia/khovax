class_name HexInput
extends RefCounted
## Turns analog input into a hex direction: the boundary where device floats become the
## simulation's integers.


## The index into Hex.DIRECTIONS closest to `input`, a screen-space vector (x right, y up), or
## Command.NO_MOVE without input. Straight up or down lies exactly between two directions: the
## row of `from` picks one, so holding it zigzags along one column.
static func direction_toward(input: Vector2, from: Vector2i) -> int:
	if input.is_zero_approx():
		return Command.NO_MOVE
	var sixths: float = fposmod(rad_to_deg(input.angle()), 360.0) / 60.0
	var index: int = roundi(sixths)
	if is_equal_approx(sixths - floorf(sixths), 0.5):
		index = floori(sixths) + posmod(from.y, 2)
	return posmod(index, Hex.DIRECTIONS.size())
