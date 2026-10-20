class_name WorldKeeper
extends Node
## Keeps the persistent world on disk (#119): at boot it hands the driver the saved world to resume,
## and while the game goes on it saves the world the driver hands it as each session starts (#831),
## debounced like the profile (#73): at most once per ProfileKeeper.SAVE_INTERVAL_MSEC, and at once
## when the game quits or goes to the background. A crash loses at most one interval of play. The
## world file is apart from the profile (WorldSave), so saving one never touches the other. What
## other slices keep beside the world (its `companions`, like the ground explored in it) is saved in
## the same file at the same moments, so the two go together. While any of its `holds` holds the
## world (an open dialog, #913), it isn't saved at all, not even on quitting, and once the last one
## lets go it's saved AFTER_HOLD_MSEC later, without waiting for the interval.

## How long after the last hold lets go the world is saved (#913).
const AFTER_HOLD_MSEC: int = 500
## No hold let go with its save still waiting.
const NOT_FREED: int = -1

## Where the main scene's keeper keeps the world unless it's pointed elsewhere; "" keeps none. The
## headless flows and the test builds clear it before the main scene comes up, so they never
## resume or overwrite a world on this device's disk.
static var default_path: String = WorldSave.PATH

## What other slices keep beside the world in its file.
@export var companions: Array[WorldCompanion] = []
## What other slices say the world mustn't be saved through (#913).
@export var holds: Array[WorldSaveHold] = []

## The world to save, which the driver hands over as each session starts; null for none.
var world: World = null
## Where this keeper keeps the world, or "" for `default_path`; tests point it elsewhere.
var save_path: String = ""
## The world last saved and its tick then, so a world that hasn't moved isn't saved again.
var _saved_world: World = null
var _saved_tick: int = -1
var _last_save_msec: int = -ProfileKeeper.SAVE_INTERVAL_MSEC
## Whether a hold held the world when the keeper last looked, and when the last one let go, while
## its save waits, or NOT_FREED.
var _was_held: bool = false
var _freed_msec: int = NOT_FREED


func _process(_delta: float) -> void:
	_report(save_if_due(Time.get_ticks_msec()))


func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	if leaving or what == NOTIFICATION_APPLICATION_PAUSED:
		_report(flush(Time.get_ticks_msec()))


## The saved world to resume, or null for a fresh one: when no world is kept, none is saved yet,
## or the save is refused. A refused save is warned about; the fresh world's saves replace it. The
## companions take over what was kept beside it.
func saved_world() -> World:
	var saved: World = _load_saved()
	for companion: WorldCompanion in companions:
		companion.resumed(saved, path())
	return saved


## The saved world, or null when there's none to resume (`saved_world`).
func _load_saved() -> World:
	if path().is_empty():
		return null
	var saved: World = WorldSave.load_from(BlueprintSource.new(), path())
	if saved != null and not saved.problem.is_empty():
		push_warning("the saved world can't be resumed, so a fresh one starts: " + saved.problem)
		return null
	if saved != null:
		_saved_world = saved
		_saved_tick = saved.tick
	return saved


## Saves the world if it moved since the last save and that save is at least
## SAVE_INTERVAL_MSEC old, or AFTER_HOLD_MSEC after the last hold let go; never while one holds it.
## Returns why it couldn't, or "".
func save_if_due(now_msec: int) -> String:
	if _held():
		_was_held = true
		_freed_msec = NOT_FREED
		return ""
	if _was_held:
		_was_held = false
		_freed_msec = now_msec
	if _freed_msec != NOT_FREED:
		if now_msec - _freed_msec < AFTER_HOLD_MSEC:
			return ""
		_freed_msec = NOT_FREED
		return flush(now_msec)
	if now_msec - _last_save_msec < ProfileKeeper.SAVE_INTERVAL_MSEC:
		return ""
	return flush(now_msec)


## Saves the world now, at `now_msec`, if it moved since the last save and nothing holds it;
## returns why it couldn't, or "". The next regular save waits a full interval from here.
func flush(now_msec: int) -> String:
	if not _moved() or _held():
		return ""
	var beside: Dictionary = {}
	for companion: WorldCompanion in companions:
		beside.merge(companion.beside(world))
	var problem: String = WorldSave.save(world, path(), beside)
	if problem.is_empty():
		WebStorage.sync()
		_last_save_msec = now_msec
		_saved_world = world
		_saved_tick = world.tick
	return problem


## Whether any of the holds holds the world now.
func _held() -> bool:
	for hold: WorldSaveHold in holds:
		if hold.holds(world):
			return true
	return false


## Whether there's a world to keep that moved since the last save.
func _moved() -> bool:
	if path().is_empty() or world == null:
		return false
	return world != _saved_world or world.tick != _saved_tick


## Where the world is kept, or "" when none is.
func path() -> String:
	return save_path if not save_path.is_empty() else default_path


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
static func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the world couldn't be saved: " + problem)
