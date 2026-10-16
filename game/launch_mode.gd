extends Node
## Applies the launch options (#237, LaunchOptions) before the main scene loads, in every build:
## starting a world of one's choosing is the player's freedom too (owner, #237), and such a world
## is never saved over their own. Options it can't use end the game with the reason, rather than
## starting a world nobody asked for.


func _ready() -> void:
	var options: LaunchOptions = LaunchOptions.parse(OS.get_cmdline_user_args())
	if not options.problem.is_empty():
		push_error("launch options: " + options.problem)
		get_tree().quit(1)
		return
	options.apply()
