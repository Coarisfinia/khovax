class_name ExitHoldHint
extends Node3D
## The loading hint at an exit (#1010): while the walk holds because a machine still reads the
## content next door (#816, Command.waiting), each player pressing out through an exit in this
## machine's player's instance gets a few words over them saying what they wait for, and a ring of
## ink marks over their head that turns slowly, a spinner. It goes as soon as the walk goes on.
## Words and a shape, never colour alone (#68); calm, as the camera is: it turns steadily, never
## pulses or flashes. It only reads the state and the last tick's commands
## (ExitFeature.pressed_out).

## Where the words stand from the tile's centre, in world units: above the spinner, and away from
## the camera (which looks down from the +z side and never turns, FollowCamera), so they show above
## the player rather than over them.
const TEXT_AT: Vector3 = Vector3(0.0, 2.4, -1.0)
const MARKS: int = 8
## How high over the tile the spinner turns (above a player's head), its radius, each mark's size,
## and how fast it turns, in turns a second.
const SPINNER_HEIGHT: float = 2.1
const RADIUS: float = 0.6
const MARK: Vector3 = Vector3(0.26, 0.06, 0.12)
const TURNS_PER_SECOND: float = 0.4

@export var driver: Session

## The hint shown for each held player, by entity id: a piece on their tile holding the words and
## the spinner. Kept here so tests can read it.
var hints: Dictionary[int, HexPiece] = {}


func _process(delta: float) -> void:
	show_state()
	for hint: HexPiece in hints.values():
		var spinner: Node3D = hint.get_child(1) as Node3D
		spinner.rotation.y = wrapf(spinner.rotation.y - TAU * TURNS_PER_SECOND * delta, 0.0, TAU)


## Matches the hints to the players held at an exit. Called every frame; tests call it.
func show_state() -> void:
	var held: Array[Entity] = held_players()
	var held_ids: Array[int] = []
	for player: Entity in held:
		held_ids.append(player.id)
	for entity_id: int in hints.keys():
		if not held_ids.has(entity_id):
			hints[entity_id].queue_free()
			var _dropped: bool = hints.erase(entity_id)
	for player: Entity in held:
		if not hints.has(player.id):
			hints[player.id] = _add_hint()
		hints[player.id].tile = player.tile


## The players in this machine's player's instance who press out through an exit while the last
## tick held the walk for content: none while no command waits.
func held_players() -> Array[Entity]:
	var held: Array[Entity] = []
	if driver == null or driver.state == null or not Command.any_waiting(driver.last_commands):
		return held
	for player: Entity in driver.state.entities:
		if not ExitFeature.pressed_out(driver.state, player, driver.last_commands).is_empty():
			held.append(player)
	return held


func _add_hint() -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.05
	piece.add_child(_words())
	var spinner: Node3D = Node3D.new()
	spinner.position.y = SPINNER_HEIGHT
	# One gap in the ring, so its turning shows.
	InkRing.add_marks(spinner, MARKS, MARKS - 1, RADIUS, MARK)
	piece.add_child(spinner)
	add_child(piece)
	return piece


func _words() -> Label3D:
	var label: Label3D = RisingText.make(Vector2i.ZERO, tr("Loading the way ahead…"))
	label.position = TEXT_AT
	return label
