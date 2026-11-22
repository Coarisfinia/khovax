class_name BossSpecialView
extends Node3D
## The boss specials' look (#2439): shows each standing boss's special cooldown as a ring of marks
## around its feet that fills as it recharges (shape as well as colour, #68), and plays a distinct
## burst on the boss and an impact starburst on what it struck whenever its special fires
## (`WildMonsterStruck.special`). Calm, as the camera is: no shake and no full-screen flash. It
## only reads the state and the tick's events.

## The cooldown ring around a boss's feet: outside FocusMark.RADIUS so the two never overlap.
const COOLDOWN_SEGMENTS: int = 12
const COOLDOWN_RADIUS: float = 0.86
const COOLDOWN_MARK: Vector3 = Vector3(0.11, 0.05, 0.22)
## How long a boss special's caster burst and impact starburst last, in seconds.
const BURST_SECONDS: float = 0.55
const IMPACT_SPRING_SHARE: float = 0.25
## The glowing wisps rising from the boss's attack centre when its special fires.
const CASTER_WISPS: int = 6
const WISP_SIZE: float = 0.42
const WISP_SPREAD: float = 0.7
const WISP_RISE: float = 0.85
const WISP_STRENGTH: float = 1.8
const WISP_FADE: float = 2.0
const FALLBACK_ORIGIN_HEIGHT: float = 0.8
## The radial starburst rays springing out on the struck tile.
const IMPACT_RAYS: int = 6
const RAY_LENGTH: float = 0.85
const RAY_RADIUS: float = 0.13
const RAY_LEAN: float = PI / 3.0

@export var driver: Session
## The wild monsters' view, so a caster burst starts at the boss's posed attack centre when shown.
@export var wild_monsters: WildMonsterView

## The cooldown ring shown for each standing boss, by entity id. Kept here so tests can read it.
var rings: Dictionary[int, HexPiece] = {}
## The caster and impact bursts still playing, newest last. Kept here so tests can read them.
var caster_bursts: Array[Node3D] = []
var impact_bursts: Array[Node3D] = []
## The instance these visuals belong to: another instance drops them at once (#189).
var _shown: GameState


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	show_state()


## Matches the cooldown rings to the standing bosses in the state. Called every frame; tests call
## it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		_clear_all()
		_shown = driver.state
	var feature: BossSpecialFeature = (
		driver.state.feature(BossSpecialFeature.ID) as BossSpecialFeature
	)
	var wild: WildMonsterFeature = (
		driver.state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	)
	var active: Array[int] = _active_bosses(feature, wild)
	for entity_id: int in rings.keys():
		if not active.has(entity_id):
			rings[entity_id].queue_free()
			var _dropped: bool = rings.erase(entity_id)
	for entity_id: int in active:
		_update_ring(feature, wild, entity_id)


## How many of the cooldown ring's marks stand for the boss `entity_id`, or -1 without a ring.
func filled_marks(entity_id: int) -> int:
	var ring: HexPiece = rings.get(entity_id)
	if ring == null:
		return -1
	var standing: Callable = func(mark: Node) -> bool: return (mark as Node3D).visible
	return ring.get_children().filter(standing).size()


## Plays the boss's caster burst on `tile`, with glowing wisps bursting from `origin` in `color`.
func show_caster_burst(tile: Vector2i, origin: Vector3, color: Color) -> void:
	var burst: HexPiece = _make_piece(tile, 0.08)
	var ring_material: StandardMaterial3D = _unshaded_alpha(color, 0.95)
	var ring: MeshInstance3D = _ring_mesh(0.42, 0.56, ring_material)
	ring.scale = Vector3.ONE * 0.5
	burst.add_child(ring)
	var wisp_material: ShaderMaterial = _wisp_material(color)
	var local_origin: Vector3 = origin - burst.tile_position()
	var wisps: Array[MeshInstance3D] = _add_wisps(burst, wisp_material, local_origin)
	caster_bursts.append(burst)
	var tween: Tween = burst.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	var _expand: PropertyTweener = tween.tween_property(
		ring, "scale", Vector3.ONE * 1.85, BURST_SECONDS
	).set_ease(Tween.EASE_OUT)
	var _fade: PropertyTweener = tween.tween_property(
		ring_material, "albedo_color:a", 0.0, BURST_SECONDS
	).set_ease(Tween.EASE_IN)
	_tween_wisp_burst(tween, wisp_material, wisps, local_origin)
	var _done: CallbackTweener = tween.chain().tween_callback(_drop_caster.bind(burst))


## Plays the special's impact starburst on `tile` in `color`.
func show_impact_burst(tile: Vector2i, color: Color) -> void:
	var burst: HexPiece = _make_piece(tile, 0.08)
	var material: StandardMaterial3D = _unshaded_alpha(color, 0.95)
	burst.add_child(_ring_mesh(0.35, 0.5, material))
	_add_rays(burst, material)
	burst.scale = Vector3.ZERO
	impact_bursts.append(burst)
	var spring: float = BURST_SECONDS * IMPACT_SPRING_SHARE
	var settle: float = BURST_SECONDS - spring
	var tween: Tween = burst.create_tween().set_trans(Tween.TRANS_SINE)
	var _out: PropertyTweener = tween.tween_property(
		burst, "scale", Vector3.ONE * 1.15, spring
	).set_ease(Tween.EASE_OUT)
	var _grow: PropertyTweener = tween.tween_property(
		burst, "scale", Vector3.ONE * 1.4, settle
	).set_ease(Tween.EASE_OUT)
	var _fade: PropertyTweener = tween.parallel().tween_property(
		material, "albedo_color:a", 0.0, settle
	).set_ease(Tween.EASE_IN)
	var _done: CallbackTweener = tween.tween_callback(_drop_impact.bind(burst))


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	show_state()
	var wild: WildMonsterFeature = (
		driver.state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	)
	if wild == null:
		return
	for event: RefCounted in driver.local_events(events):
		var struck: WildMonsterStruck = event as WildMonsterStruck
		if struck == null or not struck.special:
			continue
		var boss: Entity = driver.state.entity(struck.monster_id)
		var sees_boss: bool = WildMonsterView.is_shown(driver.state, struck.monster_id)
		var sees_target: bool = FogView.ally_sees(driver.state, struck.tile)
		if not sees_boss and not sees_target:
			continue
		var species: String = BossSpecialFeature.special_of(wild, struck.monster_id)
		var color: Color = TypeGlow.of(species)
		if sees_boss:
			show_caster_burst(boss.tile, _origin_of(struck.monster_id, boss.tile), color)
		if sees_target and not struck.dodged:
			show_impact_burst(struck.tile, color)


func _active_bosses(feature: BossSpecialFeature, wild: WildMonsterFeature) -> Array[int]:
	var active: Array[int] = []
	if feature == null or wild == null:
		return active
	for entity_id: int in feature.bosses:
		if driver.state.entity(entity_id) == null or wild.is_fainted(entity_id):
			continue
		if feature.specials.has(BossSpecialFeature.special_of(wild, entity_id)):
			active.append(entity_id)
	return active


func _update_ring(
		feature: BossSpecialFeature,
		wild: WildMonsterFeature,
		entity_id: int,
) -> void:
	var species: String = BossSpecialFeature.special_of(wild, entity_id)
	if not rings.has(entity_id):
		rings[entity_id] = _add_cooldown_ring(TypeGlow.of(species))
	var ring: HexPiece = rings[entity_id]
	ring.tile = driver.state.entity(entity_id).tile
	ring.visible = WildMonsterView.is_shown(driver.state, entity_id)
	var total: int = feature.specials[species].cooldown_seconds * Simulation.TICKS_PER_SECOND
	var left: int = feature.cooldown_left(entity_id)
	var filled: int = COOLDOWN_SEGMENTS
	if left > 0 and total > 0:
		filled = floori(float(COOLDOWN_SEGMENTS * maxi(total - left, 0)) / float(total))
	for i: int in COOLDOWN_SEGMENTS:
		(ring.get_child(i) as Node3D).visible = i < filled


func _add_cooldown_ring(color: Color) -> HexPiece:
	var piece: HexPiece = _make_piece(Vector2i.ZERO, 0.06)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var box: BoxMesh = BoxMesh.new()
	box.size = COOLDOWN_MARK
	for i: int in COOLDOWN_SEGMENTS:
		piece.add_child(_cooldown_mark(box, material, TAU * i / COOLDOWN_SEGMENTS))
	return piece


func _cooldown_mark(box: BoxMesh, material: Material, angle: float) -> MeshInstance3D:
	var mark: MeshInstance3D = MeshInstance3D.new()
	mark.mesh = box
	mark.material_override = material
	mark.position = Vector3(sin(angle), 0.0, cos(angle)) * COOLDOWN_RADIUS
	mark.rotation.y = angle
	return mark


func _origin_of(monster_id: int, tile: Vector2i) -> Vector3:
	if wild_monsters != null and wild_monsters.figures.has(monster_id):
		var model: Node3D = wild_monsters.figures[monster_id].get_child(0) as Node3D
		var centres: Array[Vector3] = ModelPoints.attack_centres(model)
		if not centres.is_empty():
			return centres[0]
	return HexLayout.to_world(tile) + Vector3.UP * FALLBACK_ORIGIN_HEIGHT


func _add_wisps(
		burst: HexPiece,
		material: ShaderMaterial,
		origin: Vector3,
) -> Array[MeshInstance3D]:
	var quad: QuadMesh = QuadMesh.new()
	quad.material = material
	var wisps: Array[MeshInstance3D] = []
	for _i: int in CASTER_WISPS:
		var wisp: MeshInstance3D = _wisp_mesh(quad, origin)
		burst.add_child(wisp)
		wisps.append(wisp)
	return wisps


func _wisp_mesh(quad: QuadMesh, origin: Vector3) -> MeshInstance3D:
	var wisp: MeshInstance3D = MeshInstance3D.new()
	wisp.mesh = quad
	wisp.position = origin
	wisp.scale = Vector3.ONE * WISP_SIZE
	wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return wisp


func _tween_wisp_burst(
		tween: Tween,
		material: ShaderMaterial,
		wisps: Array[MeshInstance3D],
		origin: Vector3,
) -> void:
	var _glow: MethodTweener = tween.tween_method(
		func(alpha: float) -> void:
			material.set_shader_parameter(&"strength", WISP_STRENGTH * alpha),
		1.0,
		0.0,
		BURST_SECONDS,
	)
	for i: int in wisps.size():
		var angle: float = TAU * i / wisps.size()
		var goal: Vector3 = origin + Vector3(
			cos(angle) * WISP_SPREAD,
			WISP_RISE,
			sin(angle) * WISP_SPREAD,
		)
		var _move: PropertyTweener = tween.tween_property(
			wisps[i], "position", goal, BURST_SECONDS
		).set_ease(Tween.EASE_OUT)


func _add_rays(burst: HexPiece, material: Material) -> void:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = RAY_RADIUS
	cone.height = RAY_LENGTH
	for i: int in IMPACT_RAYS:
		burst.add_child(_ray(cone, material, TAU * i / IMPACT_RAYS))


func _ray(cone: CylinderMesh, material: Material, heading: float) -> Node3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = cone
	mesh.material_override = material
	mesh.position = Vector3(0.0, RAY_LENGTH / 2.0, 0.0)
	var pivot: Node3D = Node3D.new()
	pivot.rotation = Vector3(RAY_LEAN, heading, 0.0)
	pivot.rotation_order = EULER_ORDER_YXZ
	pivot.add_child(mesh)
	return pivot


func _make_piece(tile: Vector2i, offset: float) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = offset
	add_child(piece)
	piece.tile = tile
	return piece


static func _ring_mesh(inner: float, outer: float, material: Material) -> MeshInstance3D:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


static func _unshaded_alpha(color: Color, alpha: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, alpha)
	return material


static func _wisp_material(color: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = EyeGlow.SHADER
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"fade", WISP_FADE)
	material.set_shader_parameter(&"strength", WISP_STRENGTH)
	return material


func _clear_all() -> void:
	for child: Node in get_children():
		child.queue_free()
	rings.clear()
	caster_bursts.clear()
	impact_bursts.clear()


func _drop_caster(burst: Node3D) -> void:
	caster_bursts.erase(burst)
	burst.queue_free()


func _drop_impact(burst: Node3D) -> void:
	impact_bursts.erase(burst)
	burst.queue_free()
