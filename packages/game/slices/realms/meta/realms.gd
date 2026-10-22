class_name Realms
extends RefCounted
## Every realm there is (#865): the realm files in DIR, found by listing it, read on first use and
## kept, since they don't change while the game runs. Nothing assumes a single realm: the world
## starts in the instance the realms mark as the start, and an instance's exits lead where the
## realm drawing it says.

const DIR: String = "res://realms/"

static var _all: Array[Realm] = []


## Every realm, in file name order.
static func all() -> Array[Realm]:
	if _all.is_empty():
		var files: Array[String] = []
		files.assign(DirAccess.get_files_at(DIR))
		files.sort()
		for file: String in files:
			if file.ends_with(".md"):
				var realm: Realm = RealmDocument.parse(FileAccess.get_file_as_string(DIR + file))
				realm.id = file.get_basename()
				_all.append(realm)
	return _all


## The first realm, in file name order, that draws the instance `instance_id`, or null.
static func holding(instance_id: String) -> Realm:
	for realm: Realm in all():
		if realm.has(instance_id):
			return realm
	return null


## The instance the world starts in: the one the first realm marking a start marks, or "".
static func start() -> String:
	for realm: Realm in all():
		if not realm.start.is_empty():
			return realm.start
	return ""
