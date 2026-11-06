class_name PackPreload
extends RefCounted
## Loads a resource pack's files in the background, with progress (#1943). Not built yet: this
## stub loads nothing, so the content flow's check fails first.

## Each file that didn't load, as a res:// path.
var failed: PackedStringArray = []


## Starts loading `pack`'s files.
static func start(_pack: ResourcePack) -> PackPreload:
	return PackPreload.new()


## How far the loads are, from 0 to 1.
func progress() -> float:
	return 0.0


## Whether every file is done.
func is_done() -> bool:
	return true
