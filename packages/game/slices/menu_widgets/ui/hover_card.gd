class_name HoverCard
extends PanelContainer
## A small info card (#1796) below the control it describes, its `trigger`: it shows while the
## mouse is over the trigger, while the trigger has a controller's focus, and once the trigger is
## tapped or clicked, and hides once neither the mouse nor the focus is on it. It floats above the
## panel's layout (top_level), so showing it never moves the rows around it, and it hides with its
## trigger, whose child it is. The menu's theme styles it by its type variation, TYPE.

## Its theme type variation, which the menu's theme (UiTheme) gives its look.
const TYPE: StringName = &"HoverCard"
## How far above the panel it draws.
const Z_ABOVE: int = 10

## What the card says, one line each. Kept here so tests can read it.
var shown: Array[String] = []
## The control it describes.
var trigger: Control
var _lines: VBoxContainer
## Whether the mouse is over the trigger, or over the card itself: a card the mouse still points
## at stays when the focus leaves.
var _hovered: bool = false
var _over_card: bool = false


func _init() -> void:
	top_level = true
	# top_level frees it from its parent's layout, not from the draw order: it still needs to be
	# drawn above the trigger's later siblings.
	z_index = Z_ABOVE
	theme_type_variation = TYPE
	visible = false
	# It takes the clicks and taps that land on it (#1807): it may cover a button, like Ascend
	# below the evolution's item, which a tap meant for the card mustn't press.
	mouse_filter = Control.MOUSE_FILTER_STOP
	var _entered: int = mouse_entered.connect(_on_card_hovered.bind(true))
	var _exited: int = mouse_exited.connect(_on_card_hovered.bind(false))
	_lines = VBoxContainer.new()
	# Its lines pass the pointer to the card, which takes it, rather than up to the trigger.
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)


## A card describing `described`, added to it as its child.
static func attach(described: Control) -> HoverCard:
	var card: HoverCard = HoverCard.new()
	card.trigger = described
	described.add_child(card)
	var _entered: int = described.mouse_entered.connect(card._on_hovered.bind(true))
	var _exited: int = described.mouse_exited.connect(card._on_hovered.bind(false))
	var _focused: int = described.focus_entered.connect(card.open)
	var _unfocused: int = described.focus_exited.connect(card._close_unless_held)
	if described is BaseButton:
		var _pressed: int = (described as BaseButton).pressed.connect(card.open)
	return card


## Says `lines` on the card, one each.
func show_lines(lines: Array[String]) -> void:
	shown = lines
	for old: Node in _lines.get_children():
		_lines.remove_child(old)
		old.queue_free()
	for line: String in lines:
		_lines.add_child(_plain(line))


## Shows the card below its trigger, kept inside the screen.
func open() -> void:
	visible = true
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	var at: Vector2 = trigger.global_position + Vector2(0.0, trigger.size.y)
	# Above the trigger when there's no room below it, and never past the screen's right edge.
	if at.y + size.y > screen.y:
		at.y = trigger.global_position.y - size.y
	at.x = clampf(at.x, 0.0, maxf(0.0, screen.x - size.x))
	global_position = at


## A label saying `line` in full, not MenuWidgets.label: a trimmed one asks for no width, and the
## card would shrink to nothing around it.
static func _plain(line: String) -> Label:
	var said: Label = Label.new()
	said.text = line
	return said


## Hides the card, like when what it describes changes under it.
func close() -> void:
	visible = false


func _on_hovered(hovered: bool) -> void:
	_hovered = hovered
	if hovered:
		open()
	else:
		# Deferred: moving from the trigger onto the card leaves the one before it enters the other.
		_close_unless_held.call_deferred()


## The mouse came onto the card, `hovered`, or left it: it stays open while the mouse is on it, so
## the click there lands on the card, not on what it covers.
func _on_card_hovered(hovered: bool) -> void:
	_over_card = hovered
	if not hovered:
		_close_unless_held.call_deferred()


## Hides the card unless the mouse is still on its trigger or on the card, or the focus on the
## trigger.
func _close_unless_held() -> void:
	if not _hovered and not _over_card and not trigger.has_focus():
		visible = false
