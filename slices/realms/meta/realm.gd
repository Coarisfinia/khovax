class_name Realm
extends RefCounted
## A realm (#865): an assortment of instances, each of which builds itself from its region pieces.
## Its file draws the instances as a picture of where they lie relative to each other
## (RealmDocument). Code names no realm and no instance: both are ids read from the files.

## The realm's id, its file's name.
var id: String = ""
## Each instance's id (its blueprint's), by the tile it's drawn on, in reading order.
var instances: Dictionary[Vector2i, String] = {}
## Why the realm's file can't be read, or "".
var problem: String = ""
