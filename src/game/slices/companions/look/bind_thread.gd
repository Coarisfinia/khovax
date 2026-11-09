class_name BindThread
extends Node3D

enum Ending {
	HOLDING,
	RELEASED,
	SNAPPED,
}

## One crown bind's thread (CrownBindView, #1206): wisps drifting along an arc from the crown above
## a companion's head down to the wild monster it binds, and a loop of wisps turning around that
## monster, so the bound one shows by a shape, never by colour alone (#68). Each wisp is a soft
## halo facing the camera, drawn by the eyes' glow shader (EyeGlow.SHADER). It ends one of two
## ways: released, its wisps break into motes that drift apart and fade; snapped, they whip back to
## the thread's two ends and go out. Then it frees itself.

## How many wisps drift along the thread, and how many turn in the loop.
const THREAD_WISPS: int = 22
const LOOP_WISPS: int = 14
## How fast the wisps drift down the thread, in its lengths per second, and turn round the loop,
## in radians per second.
const DRIFT_SPEED: float = 0.5
const LOOP_SPIN: float = 1.6
## How high the thread arcs above the straight line from the crown to the loop, at its middle.
const ARC: float = 0.6
## How wide the loop is around its middle, and how far its wisps bob up and down as it turns.
const LOOP_RADIUS: float = 0.6
const LOOP_BOB: float = 0.06
## How wide a wisp is, and how bright.
const WISP_SIZE: float = 0.38
const STRENGTH: float = 1.6
const FADE: float = 2.0
## How long a released thread's motes take to drift apart and fade, and how far they drift; how
## long a snapped thread takes to whip back and go out.
const MOTE_SECONDS: float = 0.8
const MOTE_SPREAD: float = 0.9
const SNAP_SECONDS: float = 0.15

## Where the thread starts (the crown) and where its loop's middle is, in the world.
var crown: Vector3 = Vector3.ZERO
var middle: Vector3 = Vector3.ZERO
## How it ends, once it does, and how far along that ending it is, 0 to 1.
var ending: Ending = Ending.HOLDING
var ended: float = 0.0
var _clock: float = 0.0
var _material: ShaderMaterial = ShaderMaterial.new()


func _init(color: Color) -> void:
	_material.shader = EyeGlow.SHADER
	_material.set_shader_parameter(&"color", color)
	_material.set_shader_parameter(&"fade", FADE)
	for _wisp: int in THREAD_WISPS + LOOP_WISPS:
		add_child(_wisp_mesh())


func _process(delta: float) -> void:
	advance(delta)


## Holds the thread from `from` (the crown) to the loop around `around`, in the world.
func follow(from: Vector3, around: Vector3) -> void:
	crown = from
	middle = around


## Breaks the thread into motes: its bind let go with its strike.
func release() -> void:
	if ending == Ending.HOLDING:
		ending = Ending.RELEASED


## Snaps the thread: its bind broke early.
func snap() -> void:
	if ending == Ending.HOLDING:
		ending = Ending.SNAPPED


## Moves the thread on by `seconds`: its wisps drift on, and an ending goes on that much, freeing
## the thread once it's over.
func advance(seconds: float) -> void:
	_clock += seconds
	if ending != Ending.HOLDING:
		var lasts: float = MOTE_SECONDS if ending == Ending.RELEASED else SNAP_SECONDS
		ended = minf(ended + seconds / lasts, 1.0)
		if ended >= 1.0:
			queue_free()
			return
	place()


## Puts every wisp where it is now: along the thread, then round the loop, moved by the ending.
func place() -> void:
	var fading: float = 1.0 - ended
	_material.set_shader_parameter(&"strength", STRENGTH * fading)
	var start: Vector3 = _loop_start()
	for index: int in THREAD_WISPS:
		var along: float = fposmod(float(index) / THREAD_WISPS + _clock * DRIFT_SPEED, 1.0)
		var end: Vector3 = crown if along < 0.5 else start
		_put(index, _on_arc(start, along), end)
	for index: int in LOOP_WISPS:
		var angle: float = TAU * index / LOOP_WISPS + _clock * LOOP_SPIN
		var bob: float = LOOP_BOB * sin(angle * 2.0)
		var spot: Vector3 = middle + Vector3(
			cos(angle) * LOOP_RADIUS,
			bob,
			sin(angle) * LOOP_RADIUS,
		)
		_put(THREAD_WISPS + index, spot, middle)


## Puts the wisp `index` on `spot`, moved by the ending: released, drifting away from where it was
## and shrinking; snapped, whipped back to `end`.
func _put(index: int, spot: Vector3, end: Vector3) -> void:
	var wisp: MeshInstance3D = get_child(index) as MeshInstance3D
	var size: float = WISP_SIZE
	if ending == Ending.RELEASED:
		# Each mote drifts its own way, up and out, the same way every time.
		var way: float = index * 2.4
		var drift: Vector3 = Vector3(cos(way), 0.6, sin(way)).normalized() * MOTE_SPREAD
		spot += drift * ease(ended, 0.4)
		size *= 1.0 - 0.5 * ended
	elif ending == Ending.SNAPPED:
		spot = spot.lerp(end, ease(ended, 0.3))
	wisp.global_position = spot
	wisp.scale = Vector3.ONE * size


## Where the thread meets the loop: on its side toward the crown.
func _loop_start() -> Vector3:
	var toward: Vector3 = Vector3(crown.x - middle.x, 0.0, crown.z - middle.z)
	if toward.is_zero_approx():
		return middle
	return middle + toward.normalized() * LOOP_RADIUS


## The point `along` the arc (0 at the crown, 1 at `start`), arcing up in its middle.
func _on_arc(start: Vector3, along: float) -> Vector3:
	var top: Vector3 = (crown + start) / 2.0 + Vector3.UP * ARC
	return crown.lerp(top, along).lerp(top.lerp(start, along), along)


func _wisp_mesh() -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.material = _material
	var wisp: MeshInstance3D = MeshInstance3D.new()
	wisp.mesh = quad
	wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return wisp
