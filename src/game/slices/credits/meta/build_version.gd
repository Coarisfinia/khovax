class_name BuildVersion
extends RefCounted
## The build's version (#744), as CI stamps it, for whatever names it: the Credits tab, so a player
## reporting a bug can say which build they play, and the error log's first line (#1510).

## The setting CI stamps the build's version into (ci.yml's export job, release.yml), its own
## rather than config/version, which Godot wants as plain numbers for Windows and Android (#744).
const SETTING: String = "khovax/build_version"
## The version a build CI didn't make shows: one run from the editor or a local export.
const LOCAL_BUILD: String = "local build"


## The build's version: v<next>-dev.<run> for a dev build, the tag for a release, or LOCAL_BUILD.
static func version() -> String:
	return str(ProjectSettings.get_setting(SETTING, LOCAL_BUILD))
