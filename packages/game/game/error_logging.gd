extends Node
## Starts the error log (#1510, ErrorLog) in every build, as early as the game's own code runs:
## right after LaunchMode, whose options may move `user://` where the log is written.


func _ready() -> void:
	var _written: bool = ErrorLog.start()
