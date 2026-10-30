class_name Realms
extends RefCounted
## Every realm there is (#865): the realms the resource packs have (#1861), read on first use and
## kept, since they don't change while the game runs. Nothing assumes a single realm: the world
## starts in the instance the realms mark as the start, and an instance's exits lead where the
## realm drawing it says.

static var _all: Array[Realm] = []


## Every realm, in id order.
static func all() -> Array[Realm]:
	if _all.is_empty():
		var files: Dictionary[String, String] = ResourcePacks.realms()
		for realm_id: String in files:
			# A build may leave a realm's file out, like a test-only region's (ResourcePack.KINDS).
			if not FileAccess.file_exists(files[realm_id]):
				continue
			var realm: Realm = RealmDocument.parse(FileAccess.get_file_as_string(files[realm_id]))
			realm.id = realm_id
			_all.append(realm)
	return _all


## The realm with the id `realm_id`, or null.
static func named(realm_id: String) -> Realm:
	for realm: Realm in all():
		if realm.id == realm_id:
			return realm
	return null


## The name the player reads for the realm `realm_id`, translated: its file's title (#1710), or
## "Unknown realm" for one there isn't. A place's name is its blueprint's
## (InstanceBlueprints.name_of).
static func name_of(realm_id: String) -> String:
	var realm: Realm = named(realm_id)
	if realm == null or realm.name.is_empty():
		return TranslationServer.tr("Unknown realm")
	return TranslationServer.tr(realm.name)


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
