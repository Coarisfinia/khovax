class_name DevelopmentWebView
extends VBoxContainer
## A dominated monster's development web on screen (#679), under fog of war (#1417): its directions
## run out from the middle like spokes, each node a step further out, and only the nodes it has
## taken and the ones open next to them show (DevelopmentWeb.open_nodes); the rest stays hidden,
## and so do the links that don't start at a taken node. Each node is a button saying in words what
## it shifts, a taken one saying so too, never by color alone (#68). While the monster has a level
## left to spend (DominatedMonster.picks_left), pressing an open node asks to take it (node_chosen);
## what keeps the profile takes it (Profile.take_node). The buttons sit where they show, so a
## controller's directions move the focus between neighbours (#438), and the focus stays on a node
## once it's taken. It only reads what it's shown.

## Asks to take `node` of the web of the dominated monster `short_id`.
signal node_chosen(short_id: String, node: String)

const TITLE: String = "Development"
const NONE_TEXT: String = "No monster selected"
const NO_WEB_TEXT: String = "Its development web can't be read"
## How many nodes it may still take, or that it takes one at its next level.
const PICKS_TEXT: String = "Nodes to take: %d"
const NO_PICKS_TEXT: String = "It takes a node each time it gains a level"
## The first line of a taken node's button.
const TAKEN_TEXT: String = "Taken"
## Each stat a node shifts, by its name in the data, in words as the detail pane names it.
const STAT_NAMES: Dictionary[String, String] = {
	"hp": "HP",
	"strength": "Strength",
	"speed": "Speed",
}
## The gap between two nodes of a direction, in font sizes, beyond the buttons' own size.
const GAP_FONTS: float = 0.5
## The width of a link to a taken node and of one between two taken nodes, in font sizes.
const OPEN_LINK_FONTS: float = 0.1
const TAKEN_LINK_FONTS: float = 0.3

## What the view says above the web, one line each. Kept here so tests can read it.
var shown: Array[String] = []
## The button of each node it shows, by node id, hidden ones left out. Kept here for tests.
var buttons: Dictionary[String, Button] = {}
## The monster shown, by short id, its species and the nodes it has taken, with its picks left:
## the web is built anew only when one of them changes.
var _key: Array = []
## The node whose button takes the focus once the web is built anew: the one just chosen.
var _focus_next: String = ""
var _lines: VBoxContainer
var _web: Control
## The web shown, or null.
var _shown_web: DevelopmentWeb
var _taken: Array[String] = []
## How far apart two nodes of a direction are, from the buttons' size.
var _ring: float = 0.0


func _ready() -> void:
	_lines = VBoxContainer.new()
	add_child(_lines)
	_web = Control.new()
	var _drawn: int = _web.draw.connect(_draw_links)
	var _resized: int = _web.resized.connect(_place)
	add_child(_web)
	show_monster(null)


func _notification(what: int) -> void:
	# The font decides the buttons' size, and so where they go.
	if what == NOTIFICATION_THEME_CHANGED and _web != null:
		_place.call_deferred()


## Shows `monster`'s web, or says none is selected.
func show_monster(monster: DominatedMonster) -> void:
	var key: Array = []
	if monster != null:
		key = [monster.short_id, monster.species, monster.taken.duplicate(), monster.picks_left()]
	if key == _key and not shown.is_empty():
		return
	_key = key
	var lines: Array[String] = [TITLE, NONE_TEXT]
	var webs: Dictionary[String, DevelopmentWeb] = DevelopmentContent.cached().webs
	_shown_web = null
	if monster != null:
		_shown_web = webs.get(monster.species)
		lines[1] = NO_WEB_TEXT
	if _shown_web != null:
		var left: int = monster.picks_left()
		lines[1] = PICKS_TEXT % left if left > 0 else NO_PICKS_TEXT
		_taken = monster.taken.duplicate()
	shown = lines
	for old: Node in _lines.get_children():
		_lines.remove_child(old)
		old.queue_free()
	for line: String in lines:
		_lines.add_child(_label(line))
	_build(monster)


## The words on a node's button: what its leaning shifts, one stat a line, after "Taken" once taken.
static func node_text(leaning: DevelopmentLeaning, taken: bool) -> String:
	var parts: Array[String] = [TAKEN_TEXT] if taken else []
	for stat: String in DevelopmentLeaning.STATS:
		var shift: int = leaning.get(stat)
		if shift != 0:
			# Thousandths of the species' stat, as a percentage.
			var percent: String = String.num(shift / 10.0)
			parts.append("%s %s%s%%" % [STAT_NAMES[stat], "+" if shift > 0 else "", percent])
	return "\n".join(parts)


## Builds a button for each node of the shown web that the fog reveals for `monster`.
func _build(monster: DominatedMonster) -> void:
	var focused: String = _focus_next
	_focus_next = ""
	for old: Node in _web.get_children():
		_web.remove_child(old)
		old.queue_free()
	buttons.clear()
	if _shown_web == null:
		_place()
		return
	var open: Array[String] = _shown_web.open_nodes(_taken)
	var can_take: bool = monster.picks_left() > 0
	for node: String in _shown_web.nodes:
		var taken: bool = _taken.has(node)
		if not taken and not open.has(node):
			continue
		var button: Button = _node_button(_shown_web.leanings[node], taken)
		button.disabled = taken or not can_take
		var _pressed: int = button.pressed.connect(_choose.bind(monster.short_id, node))
		_web.add_child(button)
		buttons[node] = button
	_place()
	if buttons.has(focused) and is_visible_in_tree():
		buttons[focused].grab_focus()


## A line of words above the web.
static func _label(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text
	return made


## A node's button, saying what `leaning` shifts and whether it's `taken`.
static func _node_button(leaning: DevelopmentLeaning, taken: bool) -> Button:
	var made: Button = Button.new()
	made.text = node_text(leaning, taken)
	# Taken or not, a node takes the focus, so a controller reaches every one to read it.
	made.focus_mode = Control.FOCUS_ALL
	return made


## Asks to take `node` for the monster `short_id`, keeping the focus on it once it's taken.
func _choose(short_id: String, node: String) -> void:
	_focus_next = node
	node_chosen.emit(short_id, node)


## Puts each button on its direction's spoke, a step further out for each step, and sizes the web
## to hold them all.
func _place() -> void:
	var biggest: Vector2 = Vector2.ZERO
	for button: Button in buttons.values():
		biggest = biggest.max(button.get_combined_minimum_size())
	var font: int = get_theme_default_font_size()
	_ring = maxf(biggest.x, biggest.y) + font * GAP_FONTS
	var reach: float = _ring * _most_steps() + maxf(biggest.x, biggest.y) * 0.5
	_web.custom_minimum_size = Vector2.ONE * 2.0 * reach
	for node: String in buttons:
		var button: Button = buttons[node]
		button.size = button.get_combined_minimum_size()
		button.position = _spot(node, _ring) - button.size * 0.5
	_web.queue_redraw()


## Where `node`'s middle goes in the web, `ring` apart from the next node of its direction.
func _spot(node: String, ring: float) -> Vector2:
	var middle: Vector2 = _web.size * 0.5
	if node.is_empty():
		return middle
	var directions: Array[String] = _directions()
	var turn: float = TAU * directions.find(node.get_slice("_", 0)) / directions.size()
	# The first direction points up, the rest follow clockwise.
	var spoke: Vector2 = Vector2.UP.rotated(turn)
	return middle + spoke * ring * node.get_slice("_", 1).to_int()


## Draws each link that starts at a taken node: from the middle to every direction's first node,
## along a direction, a bridge or a portal; a link between two taken nodes is drawn wider.
func _draw_links() -> void:
	if _shown_web == null or buttons.is_empty():
		return
	var font: int = get_theme_default_font_size()
	var color: Color = get_theme_color("font_color", "Label")
	for node: String in buttons:
		var ends: Array[String] = []
		if node.get_slice("_", 1).to_int() == 1:
			ends.append("")
		for next_to: String in _shown_web.links[node]:
			# Each pair once, from the node earlier in the web, and only where the fog lifts.
			if buttons.has(next_to) and (_taken.has(node) or _taken.has(next_to)):
				if _shown_web.nodes.find(next_to) < _shown_web.nodes.find(node):
					ends.append(next_to)
		for end: String in ends:
			var both: bool = _taken.has(node) and (end.is_empty() or _taken.has(end))
			var width: float = font * (TAKEN_LINK_FONTS if both else OPEN_LINK_FONTS)
			_web.draw_line(_spot(node, _ring), _spot(end, _ring), color, width, true)


## Each direction's id, in the web's order.
func _directions() -> Array[String]:
	var directions: Array[String] = []
	for node: String in _shown_web.nodes:
		if not directions.has(node.get_slice("_", 0)):
			directions.append(node.get_slice("_", 0))
	return directions


## How many steps out the furthest node shown is.
func _most_steps() -> int:
	var most: int = 0
	for node: String in buttons:
		most = maxi(most, node.get_slice("_", 1).to_int())
	return most
