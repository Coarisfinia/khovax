class_name PackPreload
extends RefCounted
## Loads a resource pack's textures, models, sounds and translation catalogues in the background
## (#1943), each file through ResourceLoader.load_threaded_request, and says how far it has got, for
## a loading screen to show. It keeps each file once loaded, so the pack's lookups
## (ResourcePack.texture and the like) find it in Godot's resource cache instead of reading it then;
## a lookup of a file still loading waits for that file. Without threads (the web build), Godot's
## threaded loads would each load at once as they're asked for, so the files load on the main
## thread instead, a step of them on each call to progress() or is_done(): the screen showing the
## progress draws a frame between steps rather than waiting on every file at once (#2083).

## The step for start: every file asked for at once, on the loader's threads.
const ALL_AT_ONCE: int = -1
## How long a step of a load without threads loads files for, in milliseconds, at least one file
## each: short enough that a loading screen still moves between them.
const STEP_MSEC: int = 20

## Each file still loading, as a res:// path.
var _loading: PackedStringArray = []
## Each file a load without threads hasn't loaded yet, as its res:// path and type, in order.
var _queued: Array[PackedStringArray] = []
## How long each step loads files for, in milliseconds, or ALL_AT_ONCE.
var _step_msec: int = ALL_AT_ONCE
## Each file loaded, kept so it stays in Godot's resource cache.
var _loaded: Array[Resource] = []
## How many files the loads cover, loaded, loading or failed.
var _total: int = 0
## Each file that didn't load, as a res:// path: missing, or not of its section's type.
var failed: PackedStringArray = []


## Starts loading every file of `packs`' sections that load as a resource (ResourcePack.KINDS): all
## at once on the loader's threads, or, with a `step_msec` of 0 or more, on the main thread, for
## that
## long on each call to progress() or is_done().
static func start(packs: Array[ResourcePack], step_msec: int = ALL_AT_ONCE) -> PackPreload:
	var loads: PackPreload = PackPreload.new()
	loads._step_msec = step_msec
	for pack: ResourcePack in packs:
		for kind: String in ResourcePack.KINDS:
			var type: String = ResourcePack.KINDS[kind]
			if type.is_empty():
				continue
			var files: Dictionary = pack.get(kind)
			for file: Variant in files.values():
				loads._request(pack.root + str(file), type)
	return loads


## How far the loads are, from 0 to 1: the files done, failed ones included, and each one's own
## progress while it loads. 1 once every file is done.
func progress() -> float:
	_collect()
	if _total == 0:
		return 1.0
	var done: float = float(_total - _loading.size() - _queued.size())
	for path: String in _loading:
		var parts: Array = []
		var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			path, parts
		)
		if not parts.is_empty() and parts[0] is float:
			var part: float = parts[0]
			done += part
	return done / _total


## Whether every file is done, loaded or failed.
func is_done() -> bool:
	_collect()
	return _loading.is_empty() and _queued.is_empty()


## Asks Godot to load the file at `path` as a `type` on its loader's threads, or queues it for a
## load without threads; one that doesn't exist as one fails at once, without an error from the
## loader.
func _request(path: String, type: String) -> void:
	_total += 1
	var asked: bool = ResourceLoader.exists(path, type)
	if asked and _step_msec != ALL_AT_ONCE:
		_queued.append(PackedStringArray([path, type]))
		return
	if asked:
		asked = ResourceLoader.load_threaded_request(path, type) == OK
	if asked:
		var _added: bool = _loading.append(path)
	else:
		var _failed: bool = failed.append(path)


## Takes every file that finished loading off the ones still loading, keeping what loaded, after a
## load without threads has loaded its next step.
func _collect() -> void:
	_step()
	var still: PackedStringArray = []
	for path: String in _loading:
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var _waiting: bool = still.append(path)
			ResourceLoader.THREAD_LOAD_LOADED:
				var loaded: Resource = ResourceLoader.load_threaded_get(path)
				if loaded == null:
					var _null: bool = failed.append(path)
				else:
					_loaded.append(loaded)
			_:
				var _failed: bool = failed.append(path)
	_loading = still


## Loads the queued files on the main thread, one at least, until the step's time is up.
func _step() -> void:
	var until: int = Time.get_ticks_msec() + _step_msec
	while not _queued.is_empty():
		var next: PackedStringArray = _queued.pop_front()
		var loaded: Resource = ResourceLoader.load(next[0], next[1])
		if loaded == null:
			var _failed: bool = failed.append(next[0])
		else:
			_loaded.append(loaded)
		if Time.get_ticks_msec() >= until:
			return
