extends Node
## Hands the core the tile blueprints' files from the resource packs once at start (#1901): the
## core reads its tile kinds' traits (TileKinds) but never names a slice, so game/ wires the packs'
## list in. An autoload ahead of everything that reads a tile, so a run without the main scene (the
## tests, the tools) reads them from the packs too; the packs are read here, on the main thread,
## before any background read (ContentFill) can start.


func _init() -> void:
	TileContent.read_from(ResourcePacks.tiles())
