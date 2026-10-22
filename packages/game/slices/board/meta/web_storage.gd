class_name WebStorage
extends RefCounted
## The browser's storage for the saves (#590), kept out of the core's SaveStore so the core names
## no platform. Nothing happens off the web.


## Asks the browser to keep this game's storage rather than evict it under pressure.
static func keep() -> void:
	if OS.has_feature("web"):
		var _asked: Variant = JavaScriptBridge.eval(
			"navigator.storage && navigator.storage.persist && navigator.storage.persist()"
		)


## Files land in the browser's storage only when it's synced; Godot syncs a frame later, which a
## closed tab can miss, so whoever saves syncs at once.
static func sync() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()
