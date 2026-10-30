class_name CodexPage
extends Control
## A codex page (#959): what selecting an invented name in a text opens (NameLinks), over the whole
## screen. A faction's is its lexicon entry: its name, the line saying what its name means ("Amvrel
## Velmarai: *the guild of those who chart*"), its entry, and this machine's player's standing
## with it, its current rank only (#484). A species' is its bestiary entry (#1173): its name, the
## line saying what its name means, and only what this machine's player has learned about it
## (BestiaryEntry), where selecting a place it was found in turns the page to that place's (#1175).
## A person's (#1005) is their name, its meaning and their entry, under the heading People. A
## realm's and a place's (#1175), an instance a realm draws or a variant's region of its own
## (#1448), are the same, under the headings Realms and Places, and so is a unique item's (#1449),
## under the heading Unique items. The close button at its top right, `ui_cancel` (Escape, or a
## controller's B) and the `menu` action close it, and the focus goes back to where it was.
## While it's open the game hears no input, as under the menu, but it doesn't pause: reading a
## dialog's line doesn't either. It eases in and out, never snaps, and its text grows with the
## screen. The codex book (CodexBook, #1174) opens it over the menu, which stays open under it.

const FADE_SECONDS: float = GameMenu.FADE_SECONDS
## The text's size as a share of the screen's shorter side, and never smaller than the menu's.
const FONT_SHARE: float = GameMenu.FONT_SHARE
## How much bigger the name is than the text.
const TITLE_SCALE: float = 1.6
## How wide the page's text is, in font sizes, at most the screen's width less the margins.
const WIDTH_FONTS: float = 30.0
const MARGIN: float = GameMenu.MARGIN

## This machine's player's input, which hears nothing while the page is open.
@export var input: LocalInput
## The session, whose holder keeps this machine's player's standings and, beside them, what they've
## learned about each species (BestiaryKeeper).
@export var driver: Session

## What the page shows, kept here so tests can read them: the heading, the name, the meaning line
## (as the player reads it), the entry and the standing line, or a species' bestiary entry.
var heading: Label
var title: Label
var gloss: RichTextLabel
var entry: Label
var standing: Label
var beast: BestiaryEntry
var close_button: Button
var _sheet: PanelContainer
var _column: VBoxContainer
var _fade: Tween
var _font_size: int = 0
## What had the focus before the page opened, which gets it back when it closes.
var _focused_before: Control
## Whether the game heard no input already before the page opened (the menu is open under it).
var _blocked_before: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme().duplicate()
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.add_theme_stylebox_override("panel", UiTheme.sheet(MARGIN))
	_sheet.visible = false
	_sheet.modulate.a = 0.0
	# Closed: it takes no clicks, which is also how is_open tells.
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = HBoxContainer.new()
	var middle: CenterContainer = CenterContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column = VBoxContainer.new()
	heading = MenuWidgets.label(heading_of(TextTags.FACTION))
	title = MenuWidgets.label("")
	# The name shown is translated already (_show_name), so the label doesn't look it up again.
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	gloss = RichTextLabel.new()
	gloss.bbcode_enabled = true
	gloss.fit_content = true
	entry = Label.new()
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	standing = MenuWidgets.label("")
	beast = BestiaryEntry.new()
	var _turned: int = beast.name_selected.connect(open)
	for shown: Control in [heading, title, gloss, entry, standing, beast]:
		_column.add_child(shown)
	# Only the sheet takes clicks, and only while open: fading out, the page lets them through.
	for passive: Control in [row, middle, _column, gloss]:
		passive.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(_column)
	row.add_child(middle)
	close_button = MenuWidgets.button("", close)
	close_button.icon = ResourcePacks.texture(GameMenu.CLOSE_ICON)
	close_button.tooltip_text = tr("Close the page (Escape, or B on a controller)")
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(close_button)
	_sheet.add_child(row)
	add_child(_sheet)


func _process(_delta: float) -> void:
	lay_out(get_viewport_rect().size)


## `ui_cancel` and `menu` close an open page before the dialog or the menu hear them.
func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		close()
		get_viewport().set_input_as_handled()


## Opens the page of the thing of the kind `kind` (TextTags.CODEX_KINDS) with the id `id`; whether
## it has one.
func open(kind: String, id: String) -> bool:
	var faction: Faction = FactionContent.cached().factions.get(id)
	var species: Species = SpeciesContent.cached().species.get(id)
	var person: Person = PeopleContent.cached().people.get(id)
	var item: GearItem = GearContent.cached().items.get(id)
	var shown: bool = false
	if kind == TextTags.FACTION:
		shown = _show_faction(faction)
	elif kind == TextTags.MONSTER:
		shown = _show_species(species)
	elif kind == TextTags.PERSON:
		shown = _show_person(person)
	elif kind == TextTags.REALM:
		shown = _show_realm(Realms.named(id))
	elif kind == TextTags.PLACE:
		shown = _show_place(id)
	elif kind == TextTags.UNIQUE_ITEM:
		shown = _show_unique_item(item)
	if not shown:
		push_warning("%s %s has no codex page" % [kind, id])
		return false
	if not is_open():
		_focused_before = get_viewport().gui_get_focus_owner()
	_ease(true)
	close_button.grab_focus()
	return true


## The page's heading over the name of a thing of the kind `kind` (TextTags.CODEX_KINDS): Lexicon
## over a faction's, Bestiary over a species', People over a person's (#1005), Realms over a realm's
## and Places over a place's (#1175), Unique items over a unique item's (#1449).
static func heading_of(kind: String) -> String:
	match kind:
		TextTags.FACTION:
			return TranslationServer.tr("Lexicon")
		TextTags.MONSTER:
			return TranslationServer.tr("Bestiary")
		TextTags.PERSON:
			return TranslationServer.tr("People")
		TextTags.REALM:
			return TranslationServer.tr("Realms")
		TextTags.PLACE:
			return TranslationServer.tr("Places")
		TextTags.UNIQUE_ITEM:
			return TranslationServer.tr("Unique items")
	# A kind without a page of its own (TextTags.CODEX_KINDS lists those that have one).
	return TranslationServer.tr("Codex")


## The standing line while this machine's player is neutral with a faction.
static func neutral_text() -> String:
	return TranslationServer.tr("Your standing: neutral")


## Shows `faction`'s lexicon entry; whether there is one.
func _show_faction(faction: Faction) -> bool:
	if faction == null:
		return false
	_show_name(TextTags.FACTION, TextTags.shown(tr(faction.name)), tr(faction.codex_gloss))
	entry.text = tr(faction.codex_entry)
	standing.text = _standing_line(faction)
	return true


## Shows `species`' bestiary entry, as much as this machine's player has learned; whether there is
## one.
func _show_species(species: Species) -> bool:
	if species == null:
		return false
	_show_name(TextTags.MONSTER, tr(species.name), tr(species.codex_gloss()))
	beast.show_species(species, BestiaryKeeper.of(_holder()))
	return true


## Shows `person`'s page; whether there is one.
func _show_person(person: Person) -> bool:
	if person == null:
		return false
	_show_name(TextTags.PERSON, TextTags.shown(tr(person.name)), tr(person.codex_gloss))
	entry.text = tr(person.codex_entry)
	return true


## Shows `realm`'s page; whether there is one.
func _show_realm(realm: Realm) -> bool:
	if realm == null:
		return false
	_show_name(TextTags.REALM, Realms.name_of(realm.id), tr(realm.codex_gloss))
	entry.text = tr(realm.codex_entry)
	return true


## Shows the page of the place `id`; whether there is one: an instance a realm draws, its entry
## from its blueprint, or a region of its own one of that instance's variants loads (#1448), its
## entry from that variant, as the tags that name a place say (TextTags.PLACE).
func _show_place(id: String) -> bool:
	var drawn: String = InstanceBlueprints.variant_owner(id)
	var blueprint: Blueprint = InstanceBlueprints.blueprint(id if drawn.is_empty() else drawn)
	if blueprint == null or Realms.holding(blueprint.id) == null:
		return false
	var codex: PackedStringArray = blueprint.variant_codex.get(
		id,
		PackedStringArray([blueprint.codex_entry, blueprint.codex_gloss]),
	)
	_show_name(TextTags.PLACE, InstanceBlueprints.name_of(id), tr(codex[1]))
	entry.text = tr(codex[0])
	return true


## Shows the unique item `item`'s page (#1449); whether there is one: other gear has none.
func _show_unique_item(item: GearItem) -> bool:
	if item == null or not item.is_unique():
		return false
	_show_name(TextTags.UNIQUE_ITEM, TextTags.shown(tr(item.name)), tr(item.codex[1]))
	entry.text = tr(item.codex[0])
	return true


## Shows the heading of the page of a thing of the kind `kind`, the thing's name `shown_name` and
## the line saying what it means, `meaning` (the name, then the meaning in italics); only the parts
## of the page of that kind show below them: the bestiary's, or the entry, with the standing on the
## lexicon's only.
func _show_name(kind: String, shown_name: String, meaning: String) -> void:
	heading.text = heading_of(kind)
	title.text = shown_name
	var parts: Dictionary[String, String] = {
		"name": NameLinks.escaped(shown_name), "meaning": NameLinks.escaped(meaning),
	}
	gloss.text = tr("{name}: [i]{meaning}[/i]").format(parts)
	var bestiary: bool = kind == TextTags.MONSTER
	entry.visible = not bestiary
	standing.visible = kind == TextTags.FACTION
	beast.visible = bestiary


## Closes the page, easing out; the focus goes back to where it was.
func close() -> void:
	if not is_open():
		return
	_ease(false)
	if is_instance_valid(_focused_before) and _focused_before.is_visible_in_tree():
		_focused_before.grab_focus()
	else:
		close_button.release_focus()
	_focused_before = null


## Whether the page is open: its sheet takes clicks exactly while it is (_ease).
func is_open() -> bool:
	return _sheet != null and _sheet.mouse_filter == Control.MOUSE_FILTER_STOP


## Sizes the text to a screen of `screen` pixels (tests lay it out for other screens this way).
func lay_out(screen: Vector2) -> void:
	var font: int = maxi(GameMenu.MIN_FONT, roundi(minf(screen.x, screen.y) * FONT_SHARE))
	if font != _font_size:
		_font_size = font
		theme.default_font_size = font
		title.add_theme_font_size_override("font_size", roundi(font * TITLE_SCALE))
		gloss.add_theme_font_size_override("normal_font_size", font)
		gloss.add_theme_font_size_override("italics_font_size", font)
		# Half a line between the page's parts, so the name, its meaning, the entry and the standing
		# read apart.
		_column.add_theme_constant_override("separation", roundi(font * 0.5))
		var side: float = font * GameMenu.BUTTON_FONTS
		close_button.custom_minimum_size = Vector2(side, side)
		close_button.add_theme_constant_override(
			"icon_max_width",
			roundi(font * MenuWidgets.ICON_FONTS),
		)
	var room: float = screen.x - 4.0 * MARGIN - font * GameMenu.BUTTON_FONTS
	_column.custom_minimum_size.x = minf(font * WIDTH_FONTS, room)


## The standing line for `faction`: this machine's player's current rank with it, never the others.
func _standing_line(faction: Faction) -> String:
	var holder: ProfileHolder = _holder()
	if holder == null or holder.keeper == null:
		return neutral_text()
	var value: int = holder.keeper.profile.standings.of(faction.id)
	if value == 0:
		return neutral_text()
	# The standing with its sign, and the rank the faction names it.
	var rank: String = TextTags.shown(tr(faction.rank_name(value)))
	var parts: Dictionary[String, String] = { "standing": "%+d" % value, "rank": rank }
	return tr("Your standing: {standing}, {rank}").format(parts)


## Eases the page in or out; the game hears no input while it's in.
func _ease(opening: bool) -> void:
	var was_open: bool = is_open()
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP if opening else Control.MOUSE_FILTER_IGNORE
	if input != null:
		# Opened over the menu (the codex book, #1174), closing it leaves the input as the menu has
		# it.
		if opening and not was_open:
			_blocked_before = input.blocked
		input.blocked = opening or _blocked_before
	if _fade != null:
		_fade.kill()
	_sheet.visible = true
	_fade = _sheet.create_tween()
	var _eased: PropertyTweener = _fade.tween_property(
		_sheet,
		"modulate:a",
		1.0 if opening else 0.0,
		FADE_SECONDS,
	)
	if not opening:
		var _hidden: CallbackTweener = _fade.tween_callback(_sheet.hide)


## This machine's player's profile, as the session hands it out (#1663); null without one.
func _holder() -> ProfileHolder:
	return driver.holder as ProfileHolder if driver != null else null
