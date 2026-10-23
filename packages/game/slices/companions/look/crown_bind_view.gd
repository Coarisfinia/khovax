class_name CrownBindView
extends Node3D
## The crown bind's look (#1206): while a companion's held special binds a wild monster (#1167,
## SpecialAttackFeature.bound), a thread of wisps (BindThread) runs from the crown above the
## companion's head down to that monster and loops around it, in the companion's type's colour
## (TypeGlow), following both figures through their clips. When the bind lets go with its strike,
## the thread breaks into motes, and the monster staggers (WildMonsterView plays Hit as its HP
## drop); when it breaks early (BindBroken), the thread snaps, without a stagger. The threads come
## from the state, their endings from the tick's events.

## How far above the middle of a companion's eyes its crown is, in its model's units.
const CROWN_LIFT: float = 0.35
## How high above a wild monster's tile its loop turns, in its model's units.
const LOOP_HEIGHT: float = 0.8

@export var driver: Session
## The views whose figures the threads run between.
@export var companions: CompanionView
@export var wild_monsters: WildMonsterView

## The thread of each bind shown, by its companion's entity id. Kept here so tests can read it.
var threads: Dictionary[int, BindThread] = {}
## The instance the threads belong to: another instance drops them at once (#189).
var _shown: GameState


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	show_state()


## Matches the threads to the binds in the state, each running from its companion's crown to its
## wild monster, and snaps any whose bind is gone without a word. Called every frame; tests call it
## after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		# Every thread, those still ending too.
		for thread: Node in get_children():
			thread.queue_free()
		threads.clear()
		_shown = driver.state
	var feature: SpecialAttackFeature = (
		driver.state.feature(SpecialAttackFeature.ID) as SpecialAttackFeature
	)
	var bound: Dictionary[int, int] = feature.bound_monsters() if feature != null else {}
	for companion_id: int in threads.keys():
		if not bound.has(companion_id):
			_end(companion_id, false)
	for companion_id: int in bound:
		var monster_id: int = bound[companion_id]
		var companion: HexPiece = companions.figures.get(companion_id)
		var monster: HexPiece = wild_monsters.figures.get(monster_id)
		if companion == null or monster == null:
			continue
		if not threads.has(companion_id):
			threads[companion_id] = _add_thread(companion_id)
		threads[companion_id].follow(crown_of(companion), loop_middle_of(monster))
		threads[companion_id].visible = monster.visible


## Ends the thread of every bind that ended this tick: broken into motes when it let go with its
## strike, snapped when it broke early. Only the shown instance's events (#1025).
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	if driver.state != _shown:
		return
	for event: RefCounted in driver.local_events(events):
		var broken: BindBroken = event as BindBroken
		if broken != null:
			_end(broken.companion_id, false)
		# A companion holding its special strikes with it only as its bind lets go.
		var struck: SpecialStruck = event as SpecialStruck
		if struck != null and struck.channel_ticks <= 0:
			_end(struck.companion_id, true)


## Ends the thread of the bind of `companion_id`, if one shows: released into motes, or snapped.
func _end(companion_id: int, released: bool) -> void:
	var thread: BindThread = threads.get(companion_id)
	if thread == null:
		return
	var _ended: bool = threads.erase(companion_id)
	if released:
		thread.release()
	else:
		thread.snap()


## Where the crown of the companion whose figure is `figure` is, in the world: above the middle of
## its eyes, which follow its clips (ModelPoints), or above its figure without eyes.
static func crown_of(figure: HexPiece) -> Vector3:
	var model: Node3D = figure.get_child(0) as Node3D
	var size: float = model.global_basis.get_scale().x
	var eyes: Array[Vector3] = ModelPoints.eyes(model)
	var middle: Vector3 = model.global_position + Vector3.UP * LOOP_HEIGHT * size
	if not eyes.is_empty():
		middle = Vector3.ZERO
		for eye: Vector3 in eyes:
			middle += eye / eyes.size()
	return middle + Vector3.UP * CROWN_LIFT * size


## Where the middle of the loop around the wild monster whose figure is `figure` is, in the world.
static func loop_middle_of(figure: HexPiece) -> Vector3:
	var model: Node3D = figure.get_child(0) as Node3D
	return model.global_position + Vector3.UP * LOOP_HEIGHT * model.global_basis.get_scale().x


## A new thread for the bind of `companion_id`, in its type's colour.
func _add_thread(companion_id: int) -> BindThread:
	var feature: CompanionFeature = driver.state.feature(CompanionFeature.ID) as CompanionFeature
	var thread: BindThread = BindThread.new(TypeGlow.of(feature.species_of(companion_id)))
	add_child(thread)
	return thread
