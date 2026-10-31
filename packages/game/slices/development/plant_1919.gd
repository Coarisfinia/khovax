extends RefCounted
## Planted for #1919 (removed in the fix): uid:// strings outside a load() or preload() call.

const PLANT_UID := "uid://b1919plantuid"


func plant() -> void:
	ResourceLoader.load_threaded_request("uid://c1919plantthreaded")
	ResourceLoader.load_threaded_request(PLANT_UID)
