extends RefCounted
## Planted for #1919 (removed in the fix): uid:// strings outside a load() or preload() call.

const PLANT_UID: String = "uid://b1919plantuid"


func plant() -> Error:
	var threaded: Error = ResourceLoader.load_threaded_request("uid://c1919plantthreaded")
	if threaded != OK:
		return threaded
	return ResourceLoader.load_threaded_request(PLANT_UID)
