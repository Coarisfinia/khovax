class_name RealmDocument
extends RefCounted
## A realm as a Markdown file, realms/<id>.md (#865): a title and prose explaining it, its
## instances drawn as an EmojiGrid in the region files' style. Each legend entry is either
## "the instance <id>", naming an instance blueprint, "the instance <id>, where the players start"
## for the instance the world starts in, or "no instance", which fills the picture between them.
## The realms are the files in DIR, found by listing it (Realms).

const INSTANCE: String = "the instance "
const START: String = ", where the players start"
const NO_INSTANCE: String = "no instance"


## Notes each instance `grid` draws on `realm`, by its tile; returns why it can't, or "".
static func _draw(realm: Realm, grid: EmojiGrid, meanings: Dictionary[String, String]) -> String:
	for tile: Vector2i in grid.symbols:
		var instance_id: String = meanings[grid.symbols[tile]]
		if realm.has(instance_id):
			return "the instance %s is drawn twice" % instance_id
		if not instance_id.is_empty():
			realm.instances[tile] = instance_id
	return ""


## The realm a Markdown realm document describes; its `problem` says what's wrong.
static func parse(text: String) -> Realm:
	var realm: Realm = Realm.new()
	var grid: EmojiGrid = EmojiGrid.read(text)
	realm.problem = grid.problem
	if not realm.problem.is_empty():
		return realm
	var starts: Array[String] = []
	var meanings: Dictionary[String, String] = _meanings(grid, starts)
	var unexplained: String = grid.unexplained(meanings)
	if not unexplained.is_empty():
		realm.problem = "the legend doesn't explain `%s`" % unexplained
	elif starts.size() > 1:
		realm.problem = "the players start in %s" % " and ".join(starts)
	else:
		realm.problem = _draw(realm, grid, meanings)
	if realm.problem.is_empty() and not starts.is_empty():
		realm.start = starts[0]
		if not realm.has(realm.start):
			realm.problem = "the players start in %s, which isn't drawn" % realm.start
	return realm


## Each legend symbol's instance id, or "" where it draws none, with the instances it marks as the
## start added to `starts`.
static func _meanings(grid: EmojiGrid, starts: Array[String]) -> Dictionary[String, String]:
	var meanings: Dictionary[String, String] = {}
	for symbol: String in grid.legend:
		var meaning: String = grid.legend[symbol]
		if meaning == NO_INSTANCE:
			meanings[symbol] = ""
		elif meaning.begins_with(INSTANCE):
			meanings[symbol] = meaning.trim_prefix(INSTANCE).trim_suffix(START)
			if meaning.ends_with(START):
				starts.append(meanings[symbol])
	return meanings
