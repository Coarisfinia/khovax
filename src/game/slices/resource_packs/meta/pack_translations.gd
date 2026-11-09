class_name PackTranslations
extends RefCounted
## Registers the resource packs' translation catalogues (#1902) with Godot's TranslationServer, in
## place of the ones registered before, so a pack can bring its own languages. A text no catalogue
## of the locale translates shows as its source text, the English that is its msgid.

## The catalogues registered last, which the next registration takes out again.
static var _registered: Array[Translation] = []


## Registers `catalogues` (ResourcePacks.translations()), taking out the ones registered before.
static func register(catalogues: Array[Translation]) -> void:
	for old: Translation in _registered:
		TranslationServer.remove_translation(old)
	_registered.clear()
	_registered.append_array(catalogues)
	for catalogue: Translation in _registered:
		TranslationServer.add_translation(catalogue)
