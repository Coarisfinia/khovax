class_name ContentCatalog
extends RefCounted
## The content read so far this session (#816), each kind kept by its key (the directory it's read
## from), so every reader after the first gets the one already read, a failed read included: the
## content is fixed data of the build and never changes while the game runs. Each `<Kind>Content`
## reads through this (its `cached`), so nothing reads a kind's files twice. Only the content flow
## and tests that write their own files read past it, with `<Kind>Content`'s own loader.
## The background fill (ContentFill) reads into it on a worker thread while the game reads from it,
## so it's thread safe: one content is read at a time, by whichever thread asks first, and a thread
## asking for one that isn't kept yet waits at most for the one being read then.

static var _kinds: Dictionary[String, Content] = {}
## Guards `_kinds`, held only for a moment, so asking whether something is kept never waits for a
## read.
static var _kept_lock: Mutex = Mutex.new()
## Held while a content is read, so no two are read at once: the readers share caches of their own
## (SchemaFields). Godot's Mutex is recursive, so a reader may read the kinds it builds on.
static var _reading: Mutex = Mutex.new()


## The content kept by `key`, read with `loader` (which returns a Content) the first time it's
## asked for.
static func kept(key: String, loader: Callable) -> Content:
	var found: Content = _found(key)
	if found != null:
		return found
	_reading.lock()
	# Another thread may have read it while this one waited.
	found = _found(key)
	if found == null:
		found = loader.call()
		_kept_lock.lock()
		_kinds[key] = found
		_kept_lock.unlock()
	_reading.unlock()
	return found


## Whether the content kept by `key` has been read.
static func has(key: String) -> bool:
	return _found(key) != null


## Drops the content kept by `key`, as if it had never been read: for tests that need content not
## read yet (#816).
static func forget(key: String) -> void:
	_kept_lock.lock()
	var _dropped: bool = _kinds.erase(key)
	_kept_lock.unlock()


## The content kept by `key`, or null.
static func _found(key: String) -> Content:
	_kept_lock.lock()
	var found: Content = _kinds.get(key)
	_kept_lock.unlock()
	return found
