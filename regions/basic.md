# Basic

The playground, the tests' own instance (#712): no exit leads to it or out of it, so normal play never reaches it, and the tests load it directly. A disc of radius 3, ground with a beach of sand at its southwest by the water (#321), where a wounded moss toad waits on the sand among broken crates to be dominated (#448, #452, #446). Digits mark where players 1 to 4 start, and m where a wild monster stands (a ball for now, #19), with room to walk a ring around it.

## Tiles

```
     . . . .
    . . . . .
   . . . 1 . .
  . m 3 . 4 . .
 ~ . . 2 . . .
~ ~ w k s s .
 ~ ~ k s s s
```

## Legend

- `.`: ground
- `~`: water
- `s`: sand; stepping here reaches the place beach
- `k`: crates; stepping here reaches the place beach
- `1` to `4`: where players 1 to 4 start
- `m`: a wild monster, of a species rolled from the instance blueprint's list
- `w`: a wild monster, always moss_toad, wounded, on sand
