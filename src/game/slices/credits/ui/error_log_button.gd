class_name ErrorLogButton
extends Button
## The Credits tab's error log line on the web (#1541): there the log (ErrorLog) lies in the
## browser's storage, where no player could pick it up, so this button saves it as a file, through
## the browser's download, for them to attach to a bug report like everyone else. Elsewhere the tab
## names where the file is instead (CreditsTab), and the button hides. Being a button, a controller
## reaches and presses it too.

## The name the saved file gets.
const FILE_NAME: String = "errors.log"


func _ready() -> void:
	visible = shown()
	var _saves: int = pressed.connect(save)


## Whether the button shows: on the web, while the log is written.
static func shown() -> bool:
	return OS.has_feature("web") and ErrorLog.written()


## Hands the log to the browser to save as a file.
func save() -> void:
	JavaScriptBridge.download_buffer(ErrorLog.saved(), FILE_NAME, "text/plain")
