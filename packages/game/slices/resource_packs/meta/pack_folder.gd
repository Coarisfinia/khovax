class_name PackFolder
extends RefCounted
## The folder a player's resource packs are found in, per platform (#1942), each a .pck the pack
## builder made (#1869). Where a player puts one is in the pack builder's PACK_MAKERS.md.
## - On a PC (Linux, Windows): `packs/` in the game's user folder, `user://packs/`.
## - On Android: the app's own folder on the shared storage (`getExternalFilesDir`), which a
##   player reaches over USB, unlike `user://`, which lies in the app's private storage. The app
##   needs no permission for it.
## - On the web: `user://packs/`, which is the browser's storage there.

## The folder on a PC and on the web, and on Android when its shared storage isn't there.
const USER: String = "user://packs/"
## The name of the folder on Android, inside the app's folder on the shared storage.
const ANDROID: String = "packs"

## The folder, found on the first call: Android's can only be asked from Java.
static var _path: String = ""


## The folder a player's packs are found in, ending in a slash.
static func path() -> String:
	if _path.is_empty():
		_path = _android_path() if OS.has_feature("android") else USER
	return _path


## The packs folder in the app's folder on Android's shared storage, made if it isn't there, or
## USER when the shared storage isn't mounted, which is warned about.
static func _android_path() -> String:
	var runtime: Object = null
	if Engine.has_singleton("AndroidRuntime"):
		runtime = Engine.get_singleton("AndroidRuntime")
	var activity: Object = null if runtime == null else runtime.call("getActivity")
	var folder: Object = null if activity == null else activity.call("getExternalFilesDir", ANDROID)
	if folder == null:
		push_warning("the shared storage isn't there, so resource packs come from " + USER)
		return USER
	return str(folder.call("getAbsolutePath")) + "/"
