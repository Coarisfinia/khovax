class_name KnotMark
extends HBoxContainer
## The mark of a dominated monster with a knot of its development web to take (#1443): a knot's
## shape and the words beside it, never color alone (#68). Its row on the Character tab carries it,
## and so does the menu's open button while a carried monster waits (GameMenu). It only shows: the
## knot is taken on the monster's web (DevelopmentWebView, #679).

const ICON: String = "icon_knot"

var _icon: TextureRect


func _init() -> void:
	_icon = TextureRect.new()
	_icon.texture = ResourcePacks.texture(ICON)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# White in its file, in ink like the menu's button icons.
	_icon.self_modulate = Toon.INK
	# A tap, a click or a drag reaches the mark itself, which its row hands on
	# (DominatedMonstersList).
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	var words: Label = Label.new()
	words.text = text()
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(words)


func _notification(what: int) -> void:
	# The menu scales its font with the screen; the icon follows it, as the words beside it do.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		var side: float = get_theme_default_font_size() * MenuWidgets.ICON_FONTS
		_icon.custom_minimum_size = Vector2.ONE * side


## The words beside the knot's shape.
static func text() -> String:
	return TranslationServer.tr("Knot to take")


## Whether `monster` has a knot to take: a level gained that no knot was taken for yet, as its web
## says too (DevelopmentWebView's picks line).
static func waits(monster: DominatedMonster) -> bool:
	return monster != null and monster.picks_left() > 0
