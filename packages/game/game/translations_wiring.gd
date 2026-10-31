extends Node
## Registers the resource packs' translation catalogues (#1902) once at start, so every text shows
## in the player's language from the first frame. An autoload, so a run without the main scene (the
## tests, the tools) gets them too.


func _init() -> void:
	PackTranslations.register(ResourcePacks.translations())
