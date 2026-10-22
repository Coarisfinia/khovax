class_name LaunchOptions
extends RefCounted
## Options given on the command line after `--` (#237), read the same way by the game and by the
## e2e runner, so a world can be started deterministically by hand, e.g.
## `godot --path packages/game -- --instance=lumwen_hoal --seed=42`:
## - `--seed=<n>`: a fresh world starts from this seed (0 or more) instead of rolling one.
## - `--instance=<blueprint>`: the session starts in this instance blueprint, on its start.
## - `--invincible`: this machine's player takes no damage from any hit, so they're never knocked
##   down or sent back to the spawn, while wild monsters still fight them (#1142).
## - `--user-dir=<name>`: `user://` (saves, settings, the tests' files) is the folder
## `khovax_<name>`
##   in the system's data folder instead of the project's own (#786), so local runs in parallel
##   worktrees, each given its branch name, keep apart. Without it, the default folder is used.
## A world started with a seed, an instance or invincibility is a test world: it never resumes or
## overwrites the player's saved one. The game reads them in every build (LaunchMode).

const SEED: String = "--seed="
const INSTANCE: String = "--instance="
const INVINCIBLE: String = "--invincible"
const USER_DIR: String = "--user-dir="
## The renderer's shader cache, inside the user folder.
const SHADER_CACHE: String = "shader_cache"
## The folder name `--user-dir=<name>` gives is this prefix and the name.
const USER_DIR_PREFIX: String = "khovax_"

## The seed to start from, or GameDriver.ROLLED_SEED to roll one.
var seed_value: int = GameDriver.ROLLED_SEED
## The instance blueprint to start in, or "" for the main scene's own.
var instance: String = ""
## Whether this machine's player is invincible.
var invincible: bool = false
## The name `user://` is redirected to, or "" for the default folder.
var user_dir: String = ""
## Why the options can't be used, or "" when they can.
var problem: String = ""


## The options in `args` (the user arguments, after `--`); `problem` says what's wrong. Arguments
## that don't start with `--` are a script's own (tools/godot/load_test.gd's `ticks=2000`), not
## options.
static func parse(args: PackedStringArray) -> LaunchOptions:
	var options: LaunchOptions = LaunchOptions.new()
	for arg: String in args:
		# Everything after the option's name: `--instance=lumwen_hoal=x` names no blueprint
		# `lumwen_hoal`.
		var value: String = arg.trim_prefix(SEED).trim_prefix(INSTANCE).trim_prefix(USER_DIR)
		if not arg.begins_with("--"):
			continue
		if arg.begins_with(SEED) and value.is_valid_int() and value.to_int() >= 0:
			options.seed_value = value.to_int()
		elif arg.begins_with(INSTANCE) and InstanceBlueprints.names().has(value):
			options.instance = value
		elif arg == INVINCIBLE:
			options.invincible = true
		elif arg.begins_with(USER_DIR) and value.is_valid_filename():
			options.user_dir = value
		elif arg.begins_with(USER_DIR):
			options.problem = "not a folder name: " + value
		elif arg.begins_with(INSTANCE):
			options.problem = "no instance blueprint %s; there are %s" % [
				value,
				", ".join(InstanceBlueprints.names()),
			]
		else:
			options.problem = "not an option, or not a seed of 0 or more: " + arg
		if not options.problem.is_empty():
			return options
	return options


## Whether these options start a test world rather than the player's own.
func is_test_world() -> bool:
	return seed_value != GameDriver.ROLLED_SEED or not instance.is_empty() or invincible


## Sets the options given up for the main scene, before it loads: its driver starts from the seed,
## in the instance, with this machine's player invincible, and a test world keeps no save;
## `user://` moves to the folder given. Options not given change nothing. Returns why they
## couldn't be applied, or "": a user folder that can't be created must stop the run before
## anything is saved.
func apply() -> String:
	if not user_dir.is_empty():
		var not_redirected: String = _redirect_user_dir()
		if not not_redirected.is_empty():
			return not_redirected
	if seed_value != GameDriver.ROLLED_SEED:
		GameDriver.fixed_seed = seed_value
	if not instance.is_empty():
		GameDriver.start_instance = instance
	if invincible:
		GameDriver.invincible = true
	if is_test_world():
		WorldKeeper.default_path = ""
	return ""


## Points `user://` at the folder `user_dir` names. Godot reads these settings on every `user://`
## path, so nothing read or written before (only the engine's own logs) stays in the default
## folder; it creates the user folder only at startup, so this creates the new one. Returns why it
## couldn't, or "".
func _redirect_user_dir() -> String:
	var engine_dir: String = OS.get_user_data_dir()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting(
		"application/config/custom_user_dir_name",
		USER_DIR_PREFIX + user_dir,
	)
	var made: Error = DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	if made != OK:
		return "couldn't create the user folder %s: %s" % [OS.get_user_data_dir(), made]
	_mirror_cache_folders(
		engine_dir.path_join(SHADER_CACHE),
		OS.get_user_data_dir().path_join(SHADER_CACHE),
	)
	return ""


## Gives the new user folder the shader cache's folders the renderer made in `engine_dir`, the
## folder `user://` was at startup (#1050): it saves each compiled shader into `user://` as it
## goes, so without them every save failed and every run compiled its shaders again. Folders only:
## each user folder keeps its own cache, so runs in parallel never share its files.
static func _mirror_cache_folders(from: String, to: String) -> void:
	for folder: String in DirAccess.get_directories_at(from):
		var _made: Error = DirAccess.make_dir_recursive_absolute(to.path_join(folder))
		_mirror_cache_folders(from.path_join(folder), to.path_join(folder))
