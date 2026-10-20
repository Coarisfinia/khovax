class_name WorldCompanion
extends Node
## What another slice keeps beside the world in its file (#827), like the ground explored in it:
## WorldKeeper hands each of its companions the world it resumes and asks them what to save beside
## it, so the board never names what the other slices keep there.


## Takes over what was kept beside `saved`, the world resumed from `path`; a fresh world starts
## when `saved` is null, with nothing kept beside it.
func resumed(_saved: World, _path: String) -> void:
	return


## What to save beside `world` in its file (WorldSave.save), by key.
func beside(_world: World) -> Dictionary:
	return {}
