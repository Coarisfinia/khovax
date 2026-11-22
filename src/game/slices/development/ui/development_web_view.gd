class_name DevelopmentWebView
extends VBoxContainer
## A dominated monster's development web on screen (#679), under fog of war (#1417): its innate
## core skills (special, two passives and any `core` abilities, #2409) sit at the middle, marked as
## taken from level 1 (#2418), and its directions run out from them like spokes, each node a step
## further out. Only the nodes it has
## taken and the ones open next to them show (DevelopmentWeb.open_nodes); the rest stays hidden,
## and so do the links that don't start at a taken node. Each node is a button saying in words what
## it grants (#1452): what it shifts, how much stronger the special grows, or the passive by name; a
## taken one saying so too, never by color alone (#68). While the monster has a level
## left to spend (DominatedMonster.picks_left), pressing an open node asks to take it (node_chosen);
## what keeps the profile takes it (Profile.take_node); otherwise pressing it does nothing. The
## buttons sit where they show, so a
## controller's directions move the focus between neighbours (#438), and the focus stays on a node
## once it's taken. It only reads what it's shown.

## Asks to take `node` of the web of the dominated monster `short_id`.
signal node_chosen(short_id: String, node: String)

## A node's smallest side, in font sizes, so a finger can hit it: the same as the menu's buttons
## (GameMenu.BUTTON_FONTS), which the menu sets only when the font changes, not on nodes built
## after.
const TOUCH_FONTS: float = 2.2
## How little of a step may go across, or down, before a spoke counts as lying along the other.
const SLANT: float = 0.1
## How opaque an open node is while the monster has no level left to take it with.
const WAITING_ALPHA: float = 0.6
## The gap between two nodes of a direction, in font sizes, beyond the buttons' own size.
const GAP_FONTS: float = 0.5
## The width of a link to a taken node and of one between two taken nodes, in font sizes.
const OPEN_LINK_FONTS: float = 0.1
const TAKEN_LINK_FONTS: float = 0.3
## How finely the spokes steepen to fit a narrow screen: the share of a step out that may go across
## is tried in steps of one over this.
const SQUEEZE_STEPS: int = 20
## How far a link between two directions bows out from the web's middle, in the buttons' widths with
## their gap: steepened spokes stack a direction's nodes, and a straight bridge would pass behind
## the nodes between its ends, as if they were linked instead (#1442).
const BOW_ROOMS: float = 0.75
## How many straight pieces draw a bowed link.
const BOW_PIECES: int = 16
## Widest a core skill button grows, in font sizes, before wrapping its description (#2418).
const CORE_WIDTH_FONTS: float = 26.0

## What the view says above the web, one line each. Kept here so tests can read it.
var shown: Array[String] = []
## The button of each node it shows, by node id, hidden ones left out. Kept here for tests.
var buttons: Dictionary[String, Button] = {}
## The button of each innate core skill at the web's middle, by ability id (#2418). Kept here for
## tests.
var core_buttons: Dictionary[String, Button] = {}
## The monster shown, by short id, its species and the nodes it has taken, with its picks left:
## the web is built anew only when one of them changes.
var _key: Array = []
## The node whose button takes the focus once the web is built anew: the one just chosen.
var _focus_next: String = ""
var _lines: VBoxContainer
var _web: Control
## What scrolls the web sideways.
var _across: ScrollContainer
## The buttons' width with the gap between two nodes: how far a link between two directions bows.
var _room_across: float = 0.0
## The web shown, or null.
var _shown_web: DevelopmentWeb
## Each ability's name with its path mark in words, by id, as the detail pane names it: a passive
## node's words.
var _abilities: Dictionary[String, String] = {}
var _taken: Array[String] = []
## Extra clearance beyond the first step so spoke nodes sit a gap clear of the core skill stack.
var _hub_extra: Vector2 = Vector2.ZERO
## How far a step out along a spoke goes, across and down, from the buttons' size.
var _ring: Vector2 = Vector2.ZERO
## How much of its share across each step out past the first still goes, from 0 to 1: 1 spaces the
## spokes out evenly, less steepens them so the web fits a narrow screen's width (#1442).
var _squeeze: float = 1.0


func _ready() -> void:
	_abilities = MonsterDetails.all_ability_names()
	_lines = VBoxContainer.new()
	add_child(_lines)
	_web = Control.new()
	var _drawn: int = _web.draw.connect(_draw_links)
	var _resized: int = _web.resized.connect(_place)
	# The web steepens its spokes to fit the screen's width (#1442). Should it still be wider, as
	# with a spoke lying flat, it scrolls sideways on its own: the Character tab doesn't, and its
	# outer nodes would be cut off otherwise. A controller's focus scrolls it to the focused node.
	_across = ScrollContainer.new()
	_across.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_across.follow_focus = true
	# A narrower screen leaves the web's own size alone, as it's at least its minimum: it's laid out
	# again for the room it has.
	var _narrowed: int = _across.resized.connect(_place)
	_web.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_across.add_child(_web)
	add_child(_across)
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
	var lines: Array[String] = [title_text(), tr("No monster selected")]
	var webs: Dictionary[String, DevelopmentWeb] = DevelopmentContent.cached().webs
	_shown_web = null
	if monster != null:
		_shown_web = webs.get(monster.species)
		lines[1] = tr("Its development web can't be read")
	if _shown_web != null:
		var left: int = monster.picks_left()
		lines[1] = picks_text(left) if left > 0 else no_picks_text()
		_taken = monster.taken.duplicate()
	shown = lines
	for old: Node in _lines.get_children():
		_lines.remove_child(old)
		old.queue_free()
	for line: String in lines:
		_lines.add_child(_label(line))
	_build(monster)


## The view's heading.
static func title_text() -> String:
	return TranslationServer.tr("Development")


## How many nodes, `left`, the monster may still take, through tr_n() so a language picks its
## plural form by the count (#1709).
static func picks_text(left: int) -> String:
	return TranslationServer.tr_n("Nodes to take: {count}", "Nodes to take: {count}", left).format(
		{ "count": left }
	)


## That the monster has no node left to take and takes one at its next level.
static func no_picks_text() -> String:
	return TranslationServer.tr("It takes a node each time it gains a level")


## The first line of a taken node's button.
static func taken_text() -> String:
	return TranslationServer.tr("Taken")


## The first line of a core skill's button: taken from level 1 and innate, in words (#68, #2418).
static func innate_text() -> String:
	return TranslationServer.tr("Taken (Innate)")


## The words on the button of the core skill `skill_id` (#2418): that it's taken from level 1 and
## innate (#68), its kind and name (with path mark), and what it does.
func core_text(skill_id: String) -> String:
	var parts: Array[String] = [innate_text()]
	var ability: Ability = AbilityContent.cached().abilities.get(skill_id)
	var shown_name: String = _abilities.get(skill_id, skill_id)
	if ability == null:
		parts.append(shown_name)
		return "\n".join(parts)
	parts.append(_core_heading(ability.kind, shown_name))
	parts.append(TextTags.shown(tr(ability.description)))
	return "\n".join(parts)


## A core skill's kind and name in words, matching MonsterDetails for the kit's three kinds.
func _core_heading(kind: String, shown_name: String) -> String:
	match kind:
		Ability.SPECIAL:
			return tr("Special: %s") % shown_name
		Ability.PLAYER_PASSIVE:
			return tr("Passive for you: %s") % shown_name
		Ability.SELF_PASSIVE:
			return tr("Own passive: %s") % shown_name
	return tr("Core: %s") % shown_name


## The words on the button of the shown web's `node`, after "Taken" once taken: what its leaning
## shifts, one stat a line, each stat's name `short`ened for a narrow screen; how much stronger it
## makes the special; or "Passive" and the passive's name below it (#1452).
func node_text(node: String, short: bool = false) -> String:
	var parts: Array[String] = []
	if _taken.has(node):
		parts.append(taken_text())
	if _shown_web.specials.has(node):
		# How much stronger it makes the species' special.
		parts.append(tr("Special +%s%%") % _percent(_shown_web.specials[node]))
	if _shown_web.passives.has(node):
		var passive: String = _shown_web.passives[node]
		parts.append_array([tr("Passive"), _abilities.get(passive, passive)])
	var leaning: DevelopmentLeaning = _shown_web.leanings[node]
	for stat: String in DevelopmentLeaning.STATS:
		var shift: int = leaning.get(stat)
		if shift != 0:
			var signed: String = ("+" if shift > 0 else "") + _percent(shift)
			# Named, so a translation can put the value first.
			var values: Dictionary = { "stat": _stat_name(stat, short), "shift": signed }
			parts.append(tr("{stat} {shift}%").format(values))
	return "\n".join(parts)


## The stat a node shifts, by its name in the data, in words as the detail pane names it, or
## `short`ened for a screen too narrow for the whole words even with the spokes at their steepest
## (#1442).
func _stat_name(stat: String, short: bool) -> String:
	match stat:
		"hp":
			return tr("HP")
		"strength":
			return tr("Str") if short else tr("Strength")
		"speed":
			return tr("Spd") if short else tr("Speed")
	# A stat the view doesn't know a word for yet (DevelopmentLeaning.STATS).
	return tr("Unknown stat")


## Thousandths, as a percentage: a tenth shows only when there is one.
static func _percent(thousandths: int) -> String:
	return ("%.1f" % (thousandths / 10.0)).trim_suffix(".0")


## Builds a button for each innate core skill at the middle and each node of the shown web that the
## fog reveals for `monster`.
func _build(monster: DominatedMonster) -> void:
	var focused: String = _focus_next
	_focus_next = ""
	for old: Node in _web.get_children():
		_web.remove_child(old)
		old.queue_free()
	buttons.clear()
	core_buttons.clear()
	if _shown_web == null:
		_place()
		return
	var known: SpeciesContent = SpeciesContent.cached()
	var skills: Array[String] = (
		known.core_skills(monster.species)
		if known.species.has(monster.species)
		else ([] as Array[String])
	)
	for skill_id: String in skills:
		var core_button: Button = _core_button()
		_web.add_child(core_button)
		core_buttons[skill_id] = core_button
	var open: Array[String] = _shown_web.open_nodes(_taken)
	var can_take: bool = monster.picks_left() > 0
	for node: String in _shown_web.nodes:
		var taken: bool = _taken.has(node)
		if not taken and not open.has(node):
			continue
		var button: Button = _node_button()
		# Never disabled, which would keep a controller's focus off it: a node that can't be taken
		# just does nothing when pressed. One that waits for a level fades, beside what the words
		# say (#68).
		if not taken and can_take:
			var _pressed: int = button.pressed.connect(_choose.bind(monster.short_id, node))
		elif not taken:
			button.modulate.a = WAITING_ALPHA
		_web.add_child(button)
		buttons[node] = button
	_place()
	if buttons.has(focused) and is_visible_in_tree():
		buttons[focused].grab_focus()
		# The web built anew is laid out over this frame, and following the focus at once would
		# scroll to where the node was: it's scrolled into sight on the next frame instead.
		var _next: int = get_tree().process_frame.connect(_reveal.bind(focused), CONNECT_ONE_SHOT)


## A line of words above the web.
static func _label(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text
	return made


## A node's button, its words set where it's sized (_space_out).
static func _node_button() -> Button:
	var made: Button = Button.new()
	# Taken or not, a node takes the focus, so a controller reaches every one to read it.
	made.focus_mode = Control.FOCUS_ALL
	return made


## A core skill's button at the web's middle: focusable for a controller (#438), never disabled,
## never connected to take, and wrapping its description so it fits a narrow screen.
static func _core_button() -> Button:
	var made: Button = _node_button()
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return made


## Scrolls `node`'s button into sight, if the web still shows it.
func _reveal(node: String) -> void:
	if buttons.has(node):
		_across.ensure_control_visible(buttons[node])


## Asks to take `node` for the monster `short_id`, keeping the focus on it once it's taken.
func _choose(short_id: String, node: String) -> void:
	_focus_next = node
	node_chosen.emit(short_id, node)


## Puts each button on its direction's spoke, a step further out for each step, and sizes the web
## to hold them all. Across and down are spaced apart on their own, so a node never covers the next
## one out, however wide its words.
func _place() -> void:
	if _shown_web == null:
		_web.custom_minimum_size = Vector2.ZERO
		return
	var biggest: Vector2 = _space_out(false)
	# Still too wide with the spokes at their steepest: the words are shortened (#1442).
	if _width(_squeeze, biggest.x) > _across.size.x:
		biggest = _space_out(true)
	var font: int = get_theme_default_font_size()
	var reach: Vector2 = Vector2.ZERO
	for node: String in buttons:
		reach = reach.max(_offset(node, _squeeze).abs())
	var gap: float = font * GAP_FONTS
	var core_box: Vector2 = _core_box_size(gap)
	var needed: Vector2 = (2.0 * reach + biggest).max(core_box)
	# A link bowing up or down needs the height, as the web can't scroll that way; across, a bow
	# keeps inside the web's width instead (_link_line).
	for link: PackedStringArray in _links():
		for point: Vector2 in _link_line(link[0], link[1], INF):
			needed.y = maxf(needed.y, 2.0 * absf(point.y) + font * TAKEN_LINK_FONTS)
	_web.custom_minimum_size = needed
	var cursor_y: float = _web.size.y * 0.5 - core_box.y * 0.5
	for button: Button in core_buttons.values():
		var sized: Vector2 = _measured_core(button)
		button.size = sized
		button.position = Vector2(_web.size.x * 0.5 - sized.x * 0.5, cursor_y)
		cursor_y += sized.y + gap
	for node: String in buttons:
		var button: Button = buttons[node]
		button.size = button.get_combined_minimum_size()
		button.position = _spot(node) - button.size * 0.5
	_web.queue_redraw()


## Sizes the buttons, with their words `short`ened or not, and spaces the spokes for them, as
## steep as the width the web has needs; returns the biggest button's size.
func _space_out(short: bool) -> Vector2:
	var biggest: Vector2 = Vector2.ZERO
	var font: int = get_theme_default_font_size()
	var gap: float = font * GAP_FONTS
	var core_box: Vector2 = _size_core_buttons(font, gap)
	for node: String in buttons:
		var button: Button = buttons[node]
		button.text = node_text(node, short)
		button.custom_minimum_size = Vector2.ONE * font * TOUCH_FONTS
		biggest = biggest.max(button.get_combined_minimum_size())
	var room: Vector2 = biggest + Vector2.ONE * gap
	_room_across = room.x
	_hub_extra = Vector2(
		maxf(0.0, core_box.x * 0.5 - biggest.x * 0.5),
		maxf(0.0, core_box.y * 0.5 - biggest.y * 0.5),
	)
	# The smallest share of a step that goes across, and down, on any spoke that has some.
	var least: Vector2 = Vector2.ONE
	var flat: bool = false
	for direction: int in _directions().size():
		var spoke: Vector2 = _spoke(direction).abs()
		least.x = minf(least.x, spoke.x) if spoke.x > SLANT else least.x
		least.y = minf(least.y, spoke.y) if spoke.y > SLANT else least.y
		flat = flat or spoke.y <= SLANT
	# A step down clears a node's height. Across, spokes on either side only need half a width
	# apart, but a spoke lying flat needs a whole one between its own nodes.
	_ring = Vector2(room.x * (1.0 if flat else 0.5) / least.x, room.y / least.y)
	_squeeze = _fitting_squeeze(room, biggest.x)
	return biggest


## Sizes the core skill buttons at the web's middle, wrapping each to fit the available width, and
## returns their stacked bounding size (#2418).
func _size_core_buttons(font: int, gap: float) -> Vector2:
	if core_buttons.is_empty():
		return Vector2.ZERO
	var core_width: float = font * CORE_WIDTH_FONTS
	if _across.size.x > 0.0:
		core_width = minf(core_width, _across.size.x)
	for skill_id: String in core_buttons:
		var button: Button = core_buttons[skill_id]
		button.text = core_text(skill_id)
		button.custom_minimum_size = Vector2(core_width, font * TOUCH_FONTS)
		button.size = Vector2(core_width, 0.0)
	return _core_box_size(gap)


## The bounding size of the stacked core skill buttons, separated by `gap`.
func _core_box_size(gap: float) -> Vector2:
	var box: Vector2 = Vector2.ZERO
	for button: Button in core_buttons.values():
		var sized: Vector2 = _measured_core(button)
		box.x = maxf(box.x, sized.x)
		if box.y > 0.0:
			box.y += gap
		box.y += sized.y
	return box


## A sized core skill button's width and wrapped height.
static func _measured_core(button: Button) -> Vector2:
	var sized: Vector2 = button.get_combined_minimum_size()
	return Vector2(maxf(sized.x, button.custom_minimum_size.x), sized.y)


## How much each step out past the first may go across, from 1 down, for the web to fit the width
## its scrolling area has: the spokes stay as even as that allows, and never steepen so far that two
## nodes `room` apart would cover each other; then the web scrolls instead (#1442).
func _fitting_squeeze(room: Vector2, biggest: float) -> float:
	var squeeze: float = 1.0
	for step: int in range(SQUEEZE_STEPS - 1, -1, -1):
		if _width(squeeze, biggest) <= _across.size.x:
			break
		var steeper: float = float(step) / SQUEEZE_STEPS
		if _covers(steeper, room):
			break
		squeeze = steeper
	return squeeze


## How wide the web is with its spokes steepened to `squeeze`, its widest node `biggest` across.
func _width(squeeze: float, biggest: float) -> float:
	var reach: float = 0.0
	for node: String in buttons:
		reach = maxf(reach, absf(_offset(node, squeeze).x))
	return maxf(2.0 * reach + biggest, _core_box_size(0.0).x)


## Whether two nodes come closer than `room` both across and down with the spokes at `squeeze`.
func _covers(squeeze: float, room: Vector2) -> bool:
	var nodes: Array[String] = []
	nodes.assign(buttons.keys())
	for first: int in nodes.size():
		var at: Vector2 = _offset(nodes[first], squeeze)
		for second: int in range(first + 1, nodes.size()):
			var apart: Vector2 = (at - _offset(nodes[second], squeeze)).abs()
			# A pixel's leeway for rounding, as neighbours on a spoke sit exactly `room` apart.
			if apart.x < room.x - 1.0 and apart.y < room.y - 1.0:
				return true
	return false


## Where `node`'s middle goes in the web, or the web's middle for "".
func _spot(node: String) -> Vector2:
	return _web.size * 0.5 + _offset(node, _squeeze)


## How far `node` sits from the web's middle with the spokes at `squeeze`: a whole step down for
## each step out, and across the first step whole and each one past it `squeeze` of one, pushed
## clear of the core skill stack at the middle.
func _offset(node: String, squeeze: float) -> Vector2:
	if node.is_empty():
		return Vector2.ZERO
	var unit: Vector2 = _spoke(_directions().find(node.get_slice("_", 0)))
	var spoke: Vector2 = unit * _ring
	var steps: int = node.get_slice("_", 1).to_int()
	var at: Vector2 = Vector2(spoke.x * (1.0 + (steps - 1) * squeeze), spoke.y * steps)
	if absf(unit.y) > SLANT:
		at.y += signf(unit.y) * _hub_extra.y
	elif absf(unit.x) > SLANT:
		at.x += signf(unit.x) * _hub_extra.x
	return at


## Which way the direction in place `direction` of the web's order runs out from the middle:
## clockwise from the top, each half a turn's share off it, so four directions run diagonally.
func _spoke(direction: int) -> Vector2:
	return Vector2.UP.rotated(TAU * (direction + 0.5) / _directions().size())


## Draws each link that starts at a taken node: from the middle to every direction's first node,
## along a direction, a bridge or a portal; a link between two taken nodes is drawn wider.
func _draw_links() -> void:
	if _shown_web == null or (buttons.is_empty() and core_buttons.is_empty()):
		return
	var font: int = get_theme_default_font_size()
	var color: Color = get_theme_color("font_color", "Label")
	for link: PackedStringArray in _links():
		var both: bool = _taken.has(link[0]) and (link[1].is_empty() or _taken.has(link[1]))
		var width: float = font * (TAKEN_LINK_FONTS if both else OPEN_LINK_FONTS)
		var side: float = _web.size.x * 0.5 - font * TAKEN_LINK_FONTS
		var line: PackedVector2Array = _link_line(link[0], link[1], side)
		_web.draw_polyline(Transform2D(0.0, _web.size * 0.5) * line, color, width, true)
	var core: Array[Button] = core_buttons.values()
	if core.size() > 1:
		var first_button: Button = core[0]
		var last_button: Button = core[core.size() - 1]
		var spine: PackedVector2Array = PackedVector2Array(
			[
				first_button.position + first_button.size * 0.5,
				last_button.position + last_button.size * 0.5,
			]
		)
		_web.draw_polyline(spine, color, font * TAKEN_LINK_FONTS, true)


## Each link the web draws, as its two nodes ("" for the middle): from every direction's first
## node to the middle, and each pair of shown nodes next to each other where one is taken, once.
func _links() -> Array[PackedStringArray]:
	var links: Array[PackedStringArray] = []
	for node: String in buttons:
		if node.get_slice("_", 1).to_int() == 1:
			links.append(PackedStringArray([node, ""]))
		for next_to: String in _shown_web.links[node]:
			# Each pair once, from the node earlier in the web, and only where the fog lifts.
			if buttons.has(next_to) and (_taken.has(node) or _taken.has(next_to)):
				if _shown_web.nodes.find(next_to) < _shown_web.nodes.find(node):
					links.append(PackedStringArray([node, next_to]))
	return links


## The line from `node` to `end` ("" for the middle), around the web's middle: straight along a
## direction, and bowed out from the middle between two directions, so it passes around the nodes
## between its ends rather than behind them, as if those were linked. Its bow reaches no further
## across than `side`, where the web's edge would cut it off. A link whose middle is the web's,
## like a portal straight across, stays straight.
func _link_line(node: String, end: String, side: float) -> PackedVector2Array:
	var from: Vector2 = _offset(node, _squeeze)
	var to: Vector2 = _offset(end, _squeeze)
	var out: Vector2 = (from + to) * 0.5
	if end.is_empty() or node.get_slice("_", 0) == end.get_slice("_", 0) or out.length() < 1.0:
		return PackedVector2Array([from, to])
	# Both ends leave outward, so the line runs around the outside like a bracket; its farthest
	# point lies three quarters of the bow beyond the middle of its ends.
	var bow: Vector2 = out.normalized() * _room_across * BOW_ROOMS
	if absf(bow.x) > 0.0:
		bow *= clampf((side - absf(out.x)) / (0.75 * absf(bow.x)), 0.0, 1.0)
	var line: PackedVector2Array = PackedVector2Array()
	for piece: int in BOW_PIECES + 1:
		var along: float = float(piece) / BOW_PIECES
		var _added: bool = line.append(from.bezier_interpolate(from + bow, to + bow, to, along))
	return line


## Each direction's id, in the web's order.
func _directions() -> Array[String]:
	var directions: Array[String] = []
	for node: String in _shown_web.nodes:
		if not directions.has(node.get_slice("_", 0)):
			directions.append(node.get_slice("_", 0))
	return directions
