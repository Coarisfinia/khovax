class_name WorldKeeper
extends Node
## Keeps the persistent world on disk (#119): at boot it hands the driver the saved world to resume,
## and while the game goes on it saves the driver's world, debounced like the profile (#73): at most
## once per ProfileKeeper.SAVE_INTERVAL_MSEC, and at once when the game quits or goes to the
## background. A crash loses at most one interval of play. The world file is apart from the
## profile (WorldSave), so saving one never touches the other.

## Where the main scene's keeper keeps the world unless it's pointed elsewhere; "" keeps none. The
## headless flows and the test builds clear it before the main scene comes up, so they never
## resume or overwrite a world on this device's disk.
static var default_path: String = WorldSave.PATH

## Whose world is saved.
@export var driver: GameDriver

## Where this keeper keeps the world, or "" for `default_path`; tests point it elsewhere.
var save_path: String = ""
## The world last saved and its tick then, so a world that hasn't moved isn't saved again.
var _saved_world: World = null
var _saved_tick: int = -1
var _last_save_msec: int = -ProfileKeeper.SAVE_INTERVAL_MSEC


func _process(_delta: float) -> void:
	_report(save_if_due(Time.get_ticks_msec()))


func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	if leaving or what == NOTIFICATION_APPLICATION_PAUSED:
		_report(flush(Time.get_ticks_msec()))


## The saved world to resume, or null for a fresh one: when no world is kept, none is saved yet,
## or the save is refused. A refused save is warned about; the fresh world's saves replace it.
func saved_world() -> World:
	if path().is_empty():
		return null
	var saved: World = WorldSave.load_from(path())
	if saved != null and not saved.problem.is_empty():
		push_warning("the saved world can't be resumed, so a fresh one starts: " + saved.problem)
		return null
	if saved != null:
		_saved_world = saved
		_saved_tick = saved.tick
	return saved


## Saves the driver's world if it moved since the last save and that save is at least
## SAVE_INTERVAL_MSEC old; returns why it couldn't, or "".
func save_if_due(now_msec: int) -> String:
	if now_msec - _last_save_msec < ProfileKeeper.SAVE_INTERVAL_MSEC:
		return ""
	return flush(now_msec)


## Saves the driver's world now, at `now_msec`, if it moved since the last save; returns why it
## couldn't, or "". The next regular save waits a full interval from here.
func flush(now_msec: int) -> String:
	if not _moved():
		return ""
	var problem: String = WorldSave.save(driver.world, path())
	if problem.is_empty():
		_last_save_msec = now_msec
		_saved_world = driver.world
		_saved_tick = driver.world.tick
	return problem


## Whether there's a world to keep that moved since the last save.
func _moved() -> bool:
	if path().is_empty() or driver == null or driver.world == null:
		return false
	return driver.world != _saved_world or driver.world.tick != _saved_tick


## Where the world is kept, or "" when none is.
func path() -> String:
	return save_path if not save_path.is_empty() else default_path


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
static func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the world couldn't be saved: " + problem)
