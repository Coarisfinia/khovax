class_name HeldWalk
extends RefCounted
## Walking toward the cursor while the left mouse button is held on the world (#1567), as a held
## stick does: FocusPicker keeps the point under the cursor here, and each command steers from the
## player's tile toward it. The stick or a key steers over it while pressed (LocalInput).

## Whether the button is held: the player walks toward `_toward`.
var held: bool = false
## The point on the instance's ground (HexLayout's coordinates) under the cursor.
var _toward: Vector3 = Vector3.ZERO


## Walks toward `point` on the instance's ground from the next command on, as long as it's held.
func hold(point: Vector3) -> void:
	held = true
	_toward = point


## Ends the walk: the button was let go, or the game hears no input (#1509).
func let_go() -> void:
	held = false


## The screen-space steering (x right, y up) from `tile` toward the held point, or none while it
## isn't held or lies on `tile`, so the player stands under the cursor instead of turning on the
## spot. North is up the screen (HexLayout), so the ground's x and -z are the screen's x and y.
func steering(tile: Vector2i) -> Vector2:
	if not held or HexLayout.to_tile(_toward) == tile:
		return Vector2.ZERO
	var offset: Vector3 = _toward - HexLayout.to_world(tile)
	return Vector2(offset.x, -offset.z)
