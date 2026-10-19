# Basic

The playground, the tests' own instance (#712): no exit leads to it or out of it, so normal play never reaches it, and the tests load it directly. A disc of radius 3, ground with a beach of sand at its southwest by the water (#321), where a wounded moss toad waits on the sand among broken crates to be dominated (#448, #452, #446). Digits mark where players 1 to 4 start, and m where a wild monster stands (a ball for now, #19), with room to walk a ring around it.

## Tiles

```
     🟫🟫🟫🟫
    🟫🟫🟫🟫🟫
   🟫🟫🟫🔴🟫🟫
  🟫👾🟢🟫🟡🟫🟫
 🟦🟫🟫🔵🟫🟫🟫
🟦🟦🤕📦🐚🐚🟫
 🟦🟦📦🐚🐚🐚
```

## Legend

- `🟫`: ground
- `🟦`: water
- `🐚`: sand; stepping here reaches the place beach
- `📦`: crates; stepping here reaches the place beach
- `🔴`: where player 1 starts
- `🔵`: where player 2 starts
- `🟢`: where player 3 starts
- `🟡`: where player 4 starts
- `👾`: a wild monster, of a species rolled from the instance blueprint's list
- `🤕`: a wild monster, always moss_toad, wounded, on sand
