class_name RealmDocument
extends RefCounted
## A realm as a Markdown file, realms/<id>.md (#865): a title and prose explaining it, its
## instances drawn as an EmojiGrid in the region files' style. Each legend entry is either
## "the instance <id>", naming an instance blueprint that must exist (drawn or not), or "no
## instance", which fills the picture between them. The realms are the files in DIR, found by
## listing it.

const DIR: String = "res://realms/"
const INSTANCE: String = "the instance "
const NO_INSTANCE: String = "no instance"


## The id of every realm there is, in file name order.
static func ids() -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(DIR):
		if file.ends_with(".md"):
			found.append(file.get_basename())
	found.sort()
	return found


## The realm of this id, read from its file.
static func read(realm_id: String) -> Realm:
	var realm: Realm = parse(FileAccess.get_file_as_string(DIR + realm_id + ".md"))
	realm.id = realm_id
	return realm


## The realm a Markdown realm document describes; its `problem` says what's wrong.
static func parse(text: String) -> Realm:
	var realm: Realm = Realm.new()
	var grid: EmojiGrid = EmojiGrid.read(text)
	realm.problem = grid.problem
	if not realm.problem.is_empty():
		return realm
	# Each symbol's instance id, or "" where it draws none.
	var meanings: Dictionary[String, String] = {}
	for symbol: String in grid.legend:
		var meaning: String = grid.legend[symbol]
		if meaning == NO_INSTANCE:
			meanings[symbol] = ""
		elif meaning.begins_with(INSTANCE):
			meanings[symbol] = meaning.trim_prefix(INSTANCE)
			if not InstanceBlueprints.exists(meanings[symbol]):
				realm.problem = "the instance %s doesn't exist" % meanings[symbol]
				return realm
	var unexplained: String = grid.unexplained(meanings)
	if not unexplained.is_empty():
		realm.problem = "the legend doesn't explain `%s`" % unexplained
		return realm
	for tile: Vector2i in grid.symbols:
		var instance_id: String = meanings[grid.symbols[tile]]
		if instance_id.is_empty():
			continue
		if realm.instances.values().has(instance_id):
			realm.problem = "the instance %s is drawn twice" % instance_id
			return realm
		realm.instances[tile] = instance_id
	return realm
