class_name ErrorLogButton
extends Button
## The Credits tab's error log line on the web (#1541): there the log (ErrorLog) lies in the
## browser's storage, where no player could pick it up, so this button saves it as a file, through
## the browser's download, for them to attach to a bug report like everyone else. Elsewhere the tab
## names where the file is instead (CreditsTab), and the button hides. Being a button, a controller
## reaches and presses it too. After a save, the note under it (#1817) says the browser may ask to
## allow the download, a prompt outside the page that only a mouse or the keys answer (a second
## save in one visit, or Safari), and shows the log's newest lines, for a player with only a
## controller to read or photograph.

## The name the saved file gets.
const FILE_NAME: String = "errors.log"
## How many of the log's newest lines the note shows.
const NEWEST_LINES: int = 8

## The note shown under the button after a save; its scene sets it.
@export var note: Label


func _ready() -> void:
	visible = shown()
	var _saves: int = pressed.connect(save)


## Whether the button shows: on the web, while the log is written.
static func shown() -> bool:
	return OS.has_feature("web") and ErrorLog.written()


## Hands the log to the browser to save as a file.
func save() -> void:
	JavaScriptBridge.download_buffer(ErrorLog.saved(), FILE_NAME, "text/plain")
	if note != null:
		note.text = note_text()
		note.visible = true


## What the note says: that the browser may ask, then the log's newest lines as they are.
func note_text() -> String:
	return "\n".join([
		tr("Your browser may ask to allow the download; answer it with the mouse or keyboard."),
		tr("The log's newest lines:"),
		ErrorLog.newest(NEWEST_LINES),
	])
