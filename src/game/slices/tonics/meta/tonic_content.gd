class_name TonicContent
extends Content
## The tonics' content data (#2090), which the tonics slice owns (#412): one JSONC file per tonic,
## checked against tonics.schema.json in CI. They're the resource packs' (ResourcePacks.tonics), so
## a
## player's pack can add or replace one; the default pack's lie in resourcepacks/default/tonics/.
## Each tonic (Tonic) lists its ingredients, and each of its brews (TonicBrew) is read against them.

## The tonics' key in the content cache (ContentCatalog).
const KEY: String = "tonics"

## Every tonic, by its id.
var tonics: Dictionary[String, Tonic] = {}
## Every brew of every tonic, by its id.
var brews: Dictionary[String, TonicBrew] = {}


## Every tonic the resource packs list, read and checked.
static func load_tonics() -> TonicContent:
	return load_files(ResourcePacks.tonics())


## Every tonic in `files` (each res:// path by its id), read and checked: a file that's missing or
## broken is the problem.
static func load_files(files: Dictionary[String, String]) -> TonicContent:
	var content: TonicContent = TonicContent.new()
	content.read_files(files)
	return content


## The tonics, read once per session (ContentCatalog).
static func cached() -> TonicContent:
	return ContentCatalog.kept(KEY, load_tonics)


func add(file_id: String, text: String) -> String:
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		return Content.NOT_AN_OBJECT
	var data: Dictionary = parsed
	var tonic: Tonic = Tonic.new()
	tonic.id = Content.text_of(data.get("id"))
	var why: String = Content.unknown_field(data, SchemaFields.at(Tonic.SCHEMA))
	if why.is_empty():
		why = Content.id_problem(tonic.id, file_id)
	if why.is_empty():
		why = tonic.read(data)
	var found: Dictionary[String, TonicBrew] = {}
	if why.is_empty():
		why = _read_brews(data.get("brews"), tonic, found)
	if why.is_empty():
		tonics[tonic.id] = tonic
		brews.merge(found)
	return why


## Reads the brews `raw` of `tonic` into `found`; returns why it can't, or "": at least one, each
## once, named like no material and no other tonic's brew, since the profile counts them alike.
func _read_brews(raw: Variant, tonic: Tonic, found: Dictionary[String, TonicBrew]) -> String:
	var listed: Array = raw if raw is Array else []
	if listed.is_empty():
		return "it needs its brews"
	var materials: Array[String] = MaterialContent.cached().ids
	for entry: Variant in listed:
		var why: String = _read_brew(entry, tonic, found, materials)
		if not why.is_empty():
			return why
	return ""


## Reads the brew `raw` of `tonic` into `found`; returns why it can't, or "".
func _read_brew(
		raw: Variant,
		tonic: Tonic,
		found: Dictionary[String, TonicBrew],
		materials: Array[String],
) -> String:
	var brew: TonicBrew = TonicBrew.new()
	var why: String = brew.read(raw, tonic)
	if why.is_empty() and (found.has(brew.id) or brews.has(brew.id) or materials.has(brew.id)):
		why = "brew %s is named twice, or like a material" % brew.id
	if why.is_empty():
		found[brew.id] = brew
	return why
