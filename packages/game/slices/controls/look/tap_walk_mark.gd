class_name TapWalkMark
extends Node3D
## The mark on the tile a tap or click walks this machine's player to (#1554, TapWalk): a ring of
## ink dashes on the tapped tile while the walk is under way, gone on arrival or as soon as the walk
## stops. It stands still, with no pulse or flash (motion sickness), and its shape tells it from
## the focus mark's solid ring and the revive ring's longer dashes, not colour (#68). It only reads
## the local input.

## How many dashes the ring has, how far from the tile's centre, and each one's size.
const DASHES: int = 6
const RADIUS: float = 0.5
const DASH: Vector3 = Vector3(0.1, 0.05, 0.18)

@export var driver: Session

## The piece standing on the tapped tile, holding the dashes.
var piece: HexPiece


func _ready() -> void:
	piece = HexPiece.new()
	piece.base_offset = 0.05
	InkRing.add_marks(piece, DASHES, DASHES, RADIUS, DASH)
	add_child(piece)
	piece.visible = false


func _process(_delta: float) -> void:
	show_state()


## Puts the ring on the tile the walk under way goes to, or hides it. Called every frame; tests
## call it.
func show_state() -> void:
	var walk: TapWalk = null
	if driver != null and driver.state != null and driver.input != null:
		walk = driver.input.tap_walk
	piece.visible = walk != null and walk.walking
	if piece.visible:
		piece.tile = walk.goal
