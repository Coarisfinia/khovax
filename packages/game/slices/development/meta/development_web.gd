class_name DevelopmentWeb
extends RefCounted
## A species' development web (#677, split from #45: "not skill trees, that's a web"): the nodes
## its dominated monsters develop along, read from content data. The web has directions, each a
## line of nodes from its middle outward, and they're interwoven: bridges connect directions
## sideways, portals connect one side of the web to the other. What's taken decides what can be
## chosen: a node is open once a node next to it is taken, and every direction's first node is
## open from the start. The rest lies in fog (#1417): a player sees the taken and the open nodes
## and picks any open one (Profile.take_node). Each node is a stat leaning so far
## (DevelopmentLeaning, #1358).

## Its schema, which says the fields a web file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/development/data/development.schema.json"
## Where a direction's fields are in the schema.
const DIRECTION: String = "/properties/directions/items"
## Where a node's fields are in the schema.
const NODE: String = DIRECTION + "/properties/nodes/items"

## The species whose web it is, by id.
var species: String = ""
## Every node's id (its direction's id, then its step from 1, e.g. sturdy_2), direction by
## direction in the web's order, each from the middle outward.
var nodes: Array[String] = []
## Each node's leaning, by node id.
var leanings: Dictionary[String, DevelopmentLeaning] = {}
## The nodes next to each node, by node id: along its direction, a bridge or a portal.
var links: Dictionary[String, PackedStringArray] = {}
## Why the web couldn't be read, or "" when it could.
var problem: String = ""
## Each direction's id, in the web's order.
var _directions: Array[String] = []


## A web read from a web file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> DevelopmentWeb:
	var web: DevelopmentWeb = DevelopmentWeb.new()
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		web.problem = Content.NOT_AN_OBJECT
		return web
	var data: Dictionary = parsed
	web.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	web.species = Content.text_of(data.get("species"))
	if web.problem.is_empty() and (web.species != file_id or not Content.is_id(web.species)):
		web.problem = "its species must be the species' id, the file's name"
	if web.problem.is_empty():
		web.problem = web._read_directions(data.get("directions"))
	if web.problem.is_empty():
		web.problem = web._read_links(data.get("bridges"), true)
	if web.problem.is_empty():
		web.problem = web._read_links(data.get("portals"), false)
	return web


## The nodes open to be chosen once `taken` are: every node not taken that is a direction's first
## or next to a taken one, in the web's order.
func open_nodes(taken: Array[String]) -> Array[String]:
	var open: Array[String] = []
	for node: String in nodes:
		if taken.has(node):
			continue
		var reached: bool = _step_of(node) == 1
		for next_to: String in links[node]:
			reached = reached or taken.has(next_to)
		if reached:
			open.append(node)
	return open


## Reads the directions and their nodes, each linked to the one before it along its direction.
func _read_directions(raw: Variant) -> String:
	var directions: Array = raw if raw is Array else []
	if directions.size() < 2:
		return "its web has two directions or more"
	for raw_direction: Variant in directions:
		var direction: Dictionary = raw_direction if raw_direction is Dictionary else {}
		var unknown: String = Content.unknown_field(direction, SchemaFields.at(SCHEMA, DIRECTION))
		if not unknown.is_empty():
			return "its direction's " + unknown
		var id: String = Content.text_of(direction.get("id"))
		if RegEx.create_from_string("^[a-z]+$").search(id) == null or _directions.has(id):
			return "each direction's id is one lowercase word, unique in its web"
		_directions.append(id)
		var steps: Array = direction.get("nodes") if direction.get("nodes") is Array else []
		if steps.is_empty():
			return "direction %s has a node or more" % id
		for step: int in steps.size():
			var why: String = _read_node(steps[step], "%s_%d" % [id, step + 1])
			if not why.is_empty():
				return why
	return ""


## Reads the node `node_id` from its object `raw`, next to the one before it along its direction.
func _read_node(raw: Variant, node_id: String) -> String:
	var data: Dictionary = raw if raw is Dictionary else {}
	var unknown: String = Content.unknown_field(data, SchemaFields.at(SCHEMA, NODE))
	if not unknown.is_empty():
		return "node %s's %s" % [node_id, unknown]
	var leaning: DevelopmentLeaning = DevelopmentLeaning.new()
	var why: String = DevelopmentLeaning.read(data.get("leaning"), leaning)
	if not why.is_empty():
		return "node %s: %s" % [node_id, why]
	links[node_id] = PackedStringArray()
	if _step_of(node_id) > 1:
		_link(nodes[-1], node_id)
	nodes.append(node_id)
	leanings[node_id] = leaning
	return ""


## Reads the bridges (`bridges` true) or the portals: each links two nodes of the web in two
## different directions, a bridge's side by side and at most one step apart, a portal's each its
## direction's outermost, and none links two nodes already next to each other.
func _read_links(raw: Variant, bridges: bool) -> String:
	var kind: String = "bridge" if bridges else "portal"
	if not raw is Array:
		return "its web lists its %ss, none when it has none" % kind
	var pairs: Array = raw
	for raw_pair: Variant in pairs:
		var pair: Array = raw_pair if raw_pair is Array else []
		if pair.size() != 2 or not nodes.has(pair[0]) or not nodes.has(pair[1]):
			return "each %s links two of its web's nodes" % kind
		var ends: Array[String] = [pair[0], pair[1]]
		var sides: Array[int] = [_direction_of(ends[0]), _direction_of(ends[1])]
		if sides[0] == sides[1] or links[ends[0]].has(ends[1]):
			return "%s %s-%s links two directions' nodes not yet next to each other" % [
				kind,
				ends[0],
				ends[1],
			]
		var apart: int = posmod(sides[1] - sides[0], _directions.size())
		var beside: bool = apart == 1 or apart == _directions.size() - 1
		if bridges and (not beside or absi(_step_of(ends[0]) - _step_of(ends[1])) > 1):
			return "bridge %s-%s links nodes side by side, at most a step apart" % ends
		if not bridges and (not _outermost(ends[0]) or not _outermost(ends[1])):
			return "portal %s-%s links two directions' outermost nodes" % ends
		_link(ends[0], ends[1])
	return ""


## Puts `one` and `other` next to each other. A packed array is a value, so each is stored anew.
func _link(one: String, other: String) -> void:
	links[one] = links[one] + PackedStringArray([other])
	links[other] = links[other] + PackedStringArray([one])


## The place of `node_id`'s direction in the web's order.
func _direction_of(node_id: String) -> int:
	return _directions.find(node_id.get_slice("_", 0))


## How many steps out from the middle `node_id` is along its direction, from 1.
func _step_of(node_id: String) -> int:
	return node_id.get_slice("_", 1).to_int()


## Whether `node_id` is its direction's outermost node.
func _outermost(node_id: String) -> bool:
	return not links.has("%s_%d" % [node_id.get_slice("_", 0), _step_of(node_id) + 1])
