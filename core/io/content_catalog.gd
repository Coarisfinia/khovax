class_name ContentCatalog
extends RefCounted
## The content read so far this session (#816), each kind kept by its key (the directory it's read
## from), so every reader after the first gets the one already read, a failed read included: the
## content is fixed data of the build and never changes while the game runs. Each `<Kind>Content`
## reads through this (its `cached`), so nothing reads a kind's files twice. Only the content flow
## and tests that write their own files read past it, with `<Kind>Content`'s own loader.

static var _kinds: Dictionary[String, Content] = {}


## The content kept by `key`, read with `loader` (which returns a Content) the first time it's
## asked for.
static func kept(key: String, loader: Callable) -> Content:
	if not _kinds.has(key):
		_kinds[key] = loader.call()
	return _kinds[key]
