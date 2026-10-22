class_name NameLinks
extends RichTextLabel
## A text whose invented names can be selected (#959): it shows a text with text tags (#733) like
## TextTags.shown, and the names of the kinds that have a codex page (TextTags.CODEX_KINDS) as
## links. Selecting one raises `name_selected` with its kind and id, which opens its codex page. A
## mouse clicks a name (it underlines, and the pointer turns to a hand over it); on a touch screen
## a long press selects it, so a plain tap never does; a controller or the keyboard focuses the
## text, where the d-pad's left and right step through its names, the chosen one in bold on a
## shade (never color alone, #68), and A or Enter selects it. Up and down leave it as from any
## other control.

## A name was selected: the kind of its tag (TextTags.FACTION) and its id.
signal name_selected(kind: String, id: String)

## How long a touch must rest on a name to select it, in milliseconds.
const LONG_PRESS_MS: int = 500
## The shade behind the name a controller has chosen: the fog, a little darker.
const CHOSEN_SHADE: Color = Color(0.74, 0.76, 0.82)
## What separates a link's kind from its id in its meta: "FACTION:amvrel_velmarai".
const META_SEPARATOR: String = ":"

## The links in the text shown, in order, each as its meta ("FACTION:amvrel_velmarai").
var links: Array[String] = []
## The link a controller has chosen, its index in `links`.
var chosen: int = 0
## The text shown, its tags as written.
var _tagged: String = ""
## When the left button or a touch last went down, and whether it was a touch (Godot's emulated
## mouse), so a short tap selects nothing.
var _pressed_at: int = 0
var _touched: bool = false
var _held_long: bool = false


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var _clicked: int = meta_clicked.connect(_on_meta_clicked)
	# Deferred: a click that focuses the text must find its link in the text it pressed on.
	var _entered: int = focus_entered.connect(_render, CONNECT_DEFERRED)
	var _exited: int = focus_exited.connect(_render, CONNECT_DEFERRED)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		# Noted before the label itself hears it, which is when a release raises meta_clicked.
		if button.pressed:
			_pressed_at = Time.get_ticks_msec()
			_touched = button.device == InputEvent.DEVICE_ID_EMULATION
		else:
			_held_long = Time.get_ticks_msec() - _pressed_at >= LONG_PRESS_MS
		return
	if links.is_empty():
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var step: int = -1 if event.is_action_pressed("ui_left") else 1
		chosen = posmod(chosen + step, links.size())
		_render()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		select(links[chosen])
		accept_event()


## Shows `tagged`, a text with text tags: every tag shows its name, those with a codex page as
## links, the first one chosen.
func show_tagged(tagged: String) -> void:
	_tagged = tagged
	chosen = 0
	_render()
	focus_mode = Control.FOCUS_NONE if links.is_empty() else Control.FOCUS_ALL


## Selects the link `meta` ("FACTION:amvrel_velmarai"), as clicking it does.
func select(meta: String) -> void:
	var at: int = meta.find(META_SEPARATOR)
	name_selected.emit(meta.left(at), meta.substr(at + 1))


func _on_meta_clicked(meta: Variant) -> void:
	if _touched and not _held_long:
		return
	select(str(meta))


## Writes the text as BBCode: its tags' names, the links among them marked, the chosen one shaded
## while the text has the focus. Everything else is escaped, so a bracket in it shows as written.
func _render() -> void:
	links.clear()
	var shown: String = ""
	var from: int = 0
	for found: RegExMatch in TextTags.tags_in(_tagged):
		shown += escaped(_tagged.substr(from, found.get_start() - from))
		from = found.get_end()
		var tag_name: String = escaped(TextTags.shown(found.get_string()))
		if not TextTags.CODEX_KINDS.has(found.get_string(1)):
			shown += tag_name
			continue
		if links.size() == chosen and has_focus():
			tag_name = "[b][bgcolor=#%s]%s[/bgcolor][/b]" % [CHOSEN_SHADE.to_html(false), tag_name]
		links.append(found.get_string(1) + META_SEPARATOR + found.get_string(2))
		shown += "[url=%s]%s[/url]" % [links.back(), tag_name]
	text = shown + escaped(_tagged.substr(from))


## `plain` with its opening brackets escaped, so BBCode shows it as written.
static func escaped(plain: String) -> String:
	return plain.replace("[", "[lb]")
