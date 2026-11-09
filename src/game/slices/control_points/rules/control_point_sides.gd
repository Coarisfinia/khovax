class_name ControlPointSides
extends RefCounted
## The sides of a control point battle (#643), and a control point nobody holds. Apart from the
## feature and the legend's reader, which both name them, so neither's constants wait on the other.

const NOBODY: int = -1
const ATTACKERS: int = 0
const DEFENDERS: int = 1
## The sides that fight, each of which loses once it holds no control point.
const FIGHTING: Array[int] = [ATTACKERS, DEFENDERS]
