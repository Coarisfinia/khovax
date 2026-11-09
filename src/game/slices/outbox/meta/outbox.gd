class_name Outbox
extends RefCounted
## A profile's outbox (#771): the requests the profile has asked the world to carry out and the
## world hasn't acknowledged yet, saved with the profile. A request is posted together with what
## asks for it (finishing a territory quest posts its hand-over), in the same change to the
## profile, so a crash between the profile's save and the world's never loses it. Each rides in
## one of the player's next commands (OutboxEntry.fill), and again at the start of every session
## until the world acknowledges it (RequestApplied); the world records the ids it applied
## (OutboxReceipts), so one sent again is never applied twice. At worst, it's applied a session
## later. A request's id is a short id (ShortId, as monsters have, #791), drawn in order (#942):
## the next code (ShortId.code) above every id drawn before, every request here and every id the
## world holds for the player (catch_up), so a profile starting over, or one whose save lost its
## newest requests, never gives an id the world already applied. Drawn in order, the ids up to
## the one just below the oldest request of a kind here have all been acknowledged (`confirmed`),
## which every command carrying one of that kind tells the world, so the feature carrying out that
## kind can forget its receipts of them.

## The requests not acknowledged yet, in the order posted.
var entries: Array[OutboxEntry] = []
## The code (ShortId.code) of the newest id drawn, or of a higher one the world holds (catch_up).
var _newest: int = Command.NO_REQUEST


## Posts a request of `kind` (OutboxEntry.KINDS) with its `data`, under a new id, and returns it.
func post(kind: int, data: int) -> OutboxEntry:
	for request: OutboxEntry in entries:
		_newest = maxi(_newest, ShortId.code(request.id))
	_newest += 1
	var entry: OutboxEntry = OutboxEntry.new(ShortId.of_code(_newest), kind, data)
	entries.append(entry)
	return entry


## Draws the next ids above the request code `highest` (#942): the highest the world holds for
## the player as a session starts (OutboxReceipts.highest).
func catch_up(highest: int) -> void:
	_newest = maxi(_newest, highest)


## The code up to which every request of `kind` (OutboxEntry.KINDS) this outbox sent was
## acknowledged (#942, #968), for a command carrying one of that kind (Command.acknowledged): just
## below its oldest request of that kind, or the newest id drawn while it holds none. A request
## dropped only once acknowledged, every id of that kind below the oldest one here was; a request
## of another kind stuck here holds no mark back but its own kind's.
func confirmed(kind: int) -> int:
	var newest: int = _newest
	var oldest: int = Command.NO_REQUEST
	for request: OutboxEntry in entries:
		var code: int = ShortId.code(request.id)
		newest = maxi(newest, code)
		if request.kind == kind and (oldest == Command.NO_REQUEST or code < oldest):
			oldest = code
	return oldest - 1 if oldest != Command.NO_REQUEST else newest


## Drops the request `request` the world acknowledged; returns whether it was here.
func drop(request: String) -> bool:
	var at: int = _index_of(request)
	if at >= 0:
		_newest = maxi(_newest, ShortId.code(request))
		entries.remove_at(at)
	return at >= 0


## The outbox as save data: its requests, in the order posted.
func to_data() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for entry: OutboxEntry in entries:
		saved.append(entry.to_data())
	return saved


## Reads save data `to_data` gave into this empty outbox; returns why it can't, or "": a list of
## requests, each with a short id no other has, a kind there is and data from 0.
func load_data(stored: Variant) -> String:
	if not stored is Array:
		return "the save's outbox is malformed"
	var saved_list: Array = stored
	for item: Variant in saved_list:
		var entry: OutboxEntry = _entry_of(item)
		if entry == null or _index_of(entry.id) >= 0:
			return "the save's outbox has a malformed request, or one twice"
		entries.append(entry)
	return ""


## Where the request `request` is in the outbox, or -1.
func _index_of(request: String) -> int:
	for at: int in entries.size():
		if entries[at].id == request:
			return at
	return -1


## The request in save data `item`, or null when it's malformed: a short id, a kind there is and
## data from 0, and nothing else.
static func _entry_of(item: Variant) -> OutboxEntry:
	var fields: Dictionary = item if item is Dictionary else {}
	var id: Variant = fields.get("id")
	var entry: OutboxEntry = OutboxEntry.new(
		str(id) if ShortId.is_valid(id) else "",
		JsonNumbers.whole(fields.get("kind"), 0, DataReader.MOST, 0),
		JsonNumbers.whole(fields.get("data"), 0, DataReader.MOST, -1),
	)
	var known: bool = OutboxEntry.KINDS.has(entry.kind) and fields.size() == 3
	return entry if not entry.id.is_empty() and known and entry.data >= 0 else null
