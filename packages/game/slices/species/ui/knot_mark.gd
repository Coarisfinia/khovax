class_name KnotMark
extends HBoxContainer
## The mark of a dominated monster with a knot of its development web to take (#1443): a knot's
## shape and the words beside it, never color alone (#68). Its row on the Character tab carries it,
## and so does the menu's open button while a carried monster waits (GameMenu). It only shows: the
## knot is taken on the monster's web (DevelopmentWebView, #679).

const ICON: Texture2D = preload("res://assets/game-icons/knot.svg")
const TEXT: String = "Knot to take"
## The icon's side, in the menu's font sizes, as the menu's button icons have.
const ICON_FONTS: float = 1.3

var _icon: TextureRect


func _init() -> void:
	_icon = TextureRect.new()
	_icon.texture = ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# White in its file, in ink like the menu's button icons.
	_icon.self_modulate = Toon.INK
	add_child(_icon)
	var words: Label = Label.new()
	words.text = TEXT
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(words)


func _notification(what: int) -> void:
	# The menu scales its font with the screen; the icon follows it, as the words beside it do.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_icon.custom_minimum_size = Vector2.ONE * get_theme_default_font_size() * ICON_FONTS


## Whether `monster` has a knot to take: a level gained that no knot was taken for yet, as its web
## says too (DevelopmentWebView's picks line).
static func waits(monster: DominatedMonster) -> bool:
	return monster != null and monster.picks_left() > 0
