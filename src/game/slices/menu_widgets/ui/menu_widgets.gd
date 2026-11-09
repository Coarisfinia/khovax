class_name MenuWidgets
extends RefCounted
## The plain controls the menu's tabs and panels are built from (#851): a label on one line, a
## button, an icon button and a box of lines. They live in a slice of their own, ahead of every
## slice that shows a panel, so a panel never names the menu (GameMenu) that holds it. The menu
## sizes their text and icons with the screen (GameMenu.lay_out).

## How wide the menu's icons are, in font sizes: a little larger than the text, so they read as
## clearly.
const ICON_FONTS: float = 1.3


## A label with `text` on one line, cut short with an ellipsis rather than wrapped: a wrapped
## label's height depends on a width its container only gives it later, so the menu's size would
## lag.
static func label(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return made


## Replaces what `box` shows with one label per line of `lines`. The old labels leave it at once,
## so it never shows both.
static func show_lines(box: Container, lines: Array[String]) -> void:
	for old: Node in box.get_children():
		box.remove_child(old)
		old.queue_free()
	for line: String in lines:
		box.add_child(label(line))


## A button saying `text` that calls `pressed`.
static func button(text: String, pressed: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	var _connected: int = made.pressed.connect(pressed)
	return made


## A button showing only the icon `shown` (#459), with `tip` as its words on hover, that calls
## `pressed`.
static func icon_button(shown: Texture2D, tip: String, pressed: Callable) -> Button:
	var made: Button = with_icon(button("", pressed), shown)
	made.tooltip_text = tip
	return made


## Gives `made` the icon `shown`, beside its text, if any; the menu sizes it with the font.
static func with_icon(made: Button, shown: Texture2D) -> Button:
	made.icon = shown
	return made
