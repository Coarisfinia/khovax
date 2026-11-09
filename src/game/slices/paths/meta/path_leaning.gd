class_name PathLeaning
extends RefCounted
## How far one player's choices lean them toward each of the story's two paths (#658): a player's
## path is not one choice, their choices add up (owner, #470). Each path-marked choice (PathMark)
## leans them one further toward its path, both for a mark of both: finishing a path-marked quest
## now, picking a path-marked dialog answer (#619) and using a path-marked item (#539) once they
## exist, each through `lean`. No choice is judged: the leaning only counts, it never takes away.
## Each player's own, kept in their profile (#74); the world-changing moments read it (#603, #620).

## How many of the player's choices leaned them toward harmony, and toward supremacy.
var harmony: int = 0
var supremacy: int = 0


## Leans the player one further toward the path `mark` names (PathMark): toward both for
## PathMark.BOTH, toward neither for PathMark.NONE. Each count stops at Fixed.MAX_AMOUNT, so a save
## always holds it.
func lean(mark: String) -> void:
	if mark == PathMark.HARMONY or mark == PathMark.BOTH:
		harmony = mini(harmony + 1, Fixed.MAX_AMOUNT)
	if mark == PathMark.SUPREMACY or mark == PathMark.BOTH:
		supremacy = mini(supremacy + 1, Fixed.MAX_AMOUNT)


## The path the player leans toward: PathMark.HARMONY or SUPREMACY, whichever more of their choices
## leaned them toward, or PathMark.NONE while the two are even.
func toward() -> String:
	if harmony > supremacy:
		return PathMark.HARMONY
	if supremacy > harmony:
		return PathMark.SUPREMACY
	return PathMark.NONE
