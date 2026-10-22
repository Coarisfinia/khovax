class_name CodexBook
extends ScrollContainer
## The codex book (#1174): the menu's Codex tab, listing every entry the player has unlocked, a
## section for each kind of name under its own heading (SECTIONS), each entry's name a button that
## opens its page (CodexPage) over the menu, by a click, a tap, or a controller's A on it. A
## faction is unlocked once the player has met its name (CodexKeeper) or has a standing with it, a
## species once they have seen it (BestiaryKeeper). The book only reads them, keeps up with them
## while shown, and scrolls when the screen is too short for every entry. Its layout lives in its
## scene, codex_book.tscn (#437); the menu shows it among its gameplay tabs, as game/ hands it over
## (a child of the menu's node).

## Each kind's section, in the order shown: its kind's word (TextTags) and its heading. A kind that
## gets a codex page gets its section here.
const SECTIONS: Dictionary[String, String] = {
	TextTags.FACTION: CodexPage.LEXICON_TEXT,
	TextTags.MONSTER: CodexPage.BESTIARY_TEXT,
}
const NONE_TEXT: String = "No names met yet"

## Which names the player has met.
@export var keeper: CodexKeeper
## The page an entry opens.
@export var page: CodexPage

## The entries listed, by kind: their ids, in the order shown. Kept here so tests can read it.
var shown: Dictionary[String, Array] = {}
var _font_size: int = 0

@onready var _rows: VBoxContainer = $Middle/Rows


func _ready() -> void:
	_show({})


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Lists the entries unlocked now; builds the rows anew only when they changed, or the text's
## size did.
func refresh() -> void:
	var font: int = get_theme_default_font_size()
	_rows.custom_minimum_size.x = minf(font * GameMenu.WIDTH_FONTS, size.x)
	var unlocked: Dictionary[String, Array] = {}
	for kind: String in SECTIONS:
		var ids: Array[String] = _unlocked(kind)
		if not ids.is_empty():
			unlocked[kind] = ids
	if unlocked != shown or font != _font_size:
		_font_size = font
		_show(unlocked)


## The button of the entry of the kind `kind` with the id `id`, or null when it isn't listed.
func entry_button(kind: String, id: String) -> Button:
	return _rows.find_child("%s_%s" % [kind, id], false, false) as Button


## The ids of the kind `kind` unlocked, in the order of their names: a faction's once met or once
## the player has a standing with it, a species' once seen (the bestiary, #1173). A name that
## stands for nothing (its content is gone) is left out.
func _unlocked(kind: String) -> Array[String]:
	var ids: Array[String] = []
	if keeper == null:
		return ids
	var holder: ProfileHolder = keeper.holder
	if kind == TextTags.MONSTER:
		var bestiary: Bestiary = BestiaryKeeper.of(holder)
		if bestiary != null:
			for species: String in bestiary.levels:
				if bestiary.level_of(species) >= Bestiary.SEEN:
					ids.append(species)
	else:
		ids = keeper.met_ids(kind)
	if kind == TextTags.FACTION and holder != null and holder.keeper != null:
		var standings: Standings = holder.keeper.profile.standings
		for id: String in standings.by_faction:
			if standings.of(id) != 0 and not ids.has(id):
				ids.append(id)
	var by_name: Dictionary[String, String] = {}
	for id: String in ids:
		if _name_of(kind, id) != _tag(kind, id):
			by_name[_name_of(kind, id)] = id
	var names: Array[String] = []
	names.assign(by_name.keys())
	names.sort()
	var named: Array[String] = []
	for shown_name: String in names:
		named.append(by_name[shown_name])
	return named


## Builds the rows: each kind's heading and its entries' buttons, from `unlocked`.
func _show(unlocked: Dictionary[String, Array]) -> void:
	shown = unlocked
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	if unlocked.is_empty():
		_rows.add_child(GameMenu.label(NONE_TEXT))
	for kind: String in unlocked:
		_rows.add_child(GameMenu.label(SECTIONS[kind]))
		for id: String in unlocked[kind]:
			var entry: Button = GameMenu.button(_name_of(kind, id), _open.bind(kind, id))
			entry.name = "%s_%s" % [kind, id]
			entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
			entry.custom_minimum_size = Vector2.ONE * _font_size * GameMenu.BUTTON_FONTS
			_rows.add_child(entry)


## Opens the page of the entry of the kind `kind` with the id `id`.
func _open(kind: String, id: String) -> void:
	if page != null:
		var _opened: bool = page.open(kind, id)


## The name the tag for the thing of the kind `kind` with the id `id` shows.
static func _name_of(kind: String, id: String) -> String:
	return TextTags.shown(_tag(kind, id))


static func _tag(kind: String, id: String) -> String:
	return "${%s:%s}" % [kind, id]
