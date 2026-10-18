class_name ReviveRing
extends Node3D
## The revive ring (#488): around each knocked-down player in this machine's player's instance, a
## ring of SEGMENTS ink marks fills as an ally revives them (KnockdownFeature, #479), and empties
## again when the ally steps away. How far the revive has come shows by how many marks stand, a
## shape, not colour alone (#68). It only reads the state.

const SEGMENTS: int = 12
## The ring's radius next to a tile, and each mark's size.
const RADIUS: float = 0.8
const MARK: Vector3 = Vector3(0.12, 0.06, 0.24)

@export var driver: GameDriver

## The ring shown for each knocked-down player, by entity id: a piece on their tile holding the
## marks.
var rings: Dictionary[int, HexPiece] = {}
var _ink: StandardMaterial3D
var _box: BoxMesh


func _ready() -> void:
	_ink = StandardMaterial3D.new()
	_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ink.albedo_color = Toon.INK
	_box = BoxMesh.new()
	_box.size = MARK


func _process(_delta: float) -> void:
	show_state()


## Matches the rings to the knocked-down players and fills each with its revive. Called every
## frame; tests call it.
func show_state() -> void:
	# Without a state there's nobody to show: every ring goes.
	if driver == null or driver.state == null:
		HexPiece.free_all(rings)
		return
	var knockdown: KnockdownFeature = driver.state.feature(Features.KNOCKDOWN) as KnockdownFeature
	var down: Array[int] = knockdown.knocked_down() if knockdown != null else []
	for entity_id: int in rings.keys():
		if not down.has(entity_id) or driver.state.entity(entity_id) == null:
			rings[entity_id].queue_free()
			var _dropped: bool = rings.erase(entity_id)
	for entity_id: int in down:
		if driver.state.entity(entity_id) == null:
			continue
		if not rings.has(entity_id):
			rings[entity_id] = _add_ring()
		rings[entity_id].tile = driver.state.entity(entity_id).tile
		var revived: int = knockdown.revive_ticks(entity_id)
		var filled: int = floori(float(SEGMENTS * revived) / KnockdownFeature.REVIVE_TICKS)
		for i: int in SEGMENTS:
			(rings[entity_id].get_child(i) as Node3D).visible = i < filled


## How many of the ring's marks stand for the player `entity_id`, or -1 without a ring.
func filled_marks(entity_id: int) -> int:
	if not rings.has(entity_id):
		return -1
	var count: int = 0
	for mark: Node in rings[entity_id].get_children():
		count += 1 if (mark as Node3D).visible else 0
	return count


func _add_ring() -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.05
	for i: int in SEGMENTS:
		piece.add_child(_mark(TAU * i / SEGMENTS))
	add_child(piece)
	return piece


## One of a ring's marks, `angle` round it, facing along the ring.
func _mark(angle: float) -> MeshInstance3D:
	var mark: MeshInstance3D = MeshInstance3D.new()
	mark.mesh = _box
	mark.material_override = _ink
	mark.position = Vector3(sin(angle), 0.0, cos(angle)) * RADIUS
	mark.rotation.y = angle
	return mark
