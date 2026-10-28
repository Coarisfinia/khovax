class_name BugReportButton
extends Button
## The Credits tab's "Report a bug" button (#1405): it opens a new issue in the game's public
## repository in the browser, its body already holding the build's version (BuildVersion), the
## platform and a short template, and saying where the error log is (ErrorLog, #1510) for the
## player to attach. Nothing is sent by the game itself: the player writes and files the issue,
## which needs an account there. Being a button, a controller reaches and presses it too.

## Where a new issue is opened, its body passed in the link.
const NEW_ISSUE_URL: String = "https://github.com/Coarisfinia/khovax/issues/new?body="
## On the web the log is saved as a file by the button beside this one (ErrorLogButton, #1541).
const WEB_LOG: String = "save it with the Credits tab's error log button"
const DEVICE_LOG: String = "the file the Credits tab names under Error log"
const NO_LOG: String = "none was written"

## What opens a link in the system's browser (a new tab on the web); tests swap it so none opens.
var open_link: Callable = OS.shell_open


func _ready() -> void:
	var _reports: int = pressed.connect(report)


## Opens the new issue, as pressing the button does.
func report() -> void:
	var problem: int = open_link.call(url())
	if problem != OK:
		push_warning("the bug report can't be opened: " + error_string(problem))


## The link to a new issue with `body()` filled in.
static func url() -> String:
	return NEW_ISSUE_URL + body().uri_encode()


## The new issue's body: the template to fill in, then the build's version and the platform as the
## error log's header names them, and where the log is. The log's place on the device isn't
## written here, since its folders could name the player: the Credits tab shows it to them.
static func body() -> String:
	return "\n".join([
		"**What happened?**",
		"",
		"**What did you expect to happen?**",
		"",
		"**How can it be made to happen again?**",
		"",
		"---",
		"```",
		ErrorLog.header().strip_edges(),
		"```",
		"Error log (please attach it): " + log_place(),
		"",
	])


## Where the player finds the error log to attach: the file the Credits tab names, or on the web
## the button there that saves it.
static func log_place() -> String:
	if OS.has_feature("web"):
		return WEB_LOG if ErrorLog.written() else NO_LOG
	return DEVICE_LOG if ErrorLog.written() else NO_LOG
