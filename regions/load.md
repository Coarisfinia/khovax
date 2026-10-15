# Load test

The load test's region (#101): a disc of radius 12, the four starts in the middle and a wild monster on about every third tile from the third ring out, so the rules have plenty to do. Run tools/load_test.gd on it.

## Tiles

```
            m . . m . . m . . m . . m
           m . . m . . m . . m . . m .
          m . . m . . m . . m . . m . .
         m . . m . . m . . m . . m . . m
        m . . m . . m . . m . . m . . m .
       m . . m . . m . . m . . m . . m . .
      m . . m . . m . . m . . m . . m . . m
     m . . m . . m . . m . . m . . m . . m .
    m . . m . . m . . m . . m . . m . . m . .
   m . . m . . m . . m . . m . . m . . m . . m
  m . . m . . m . . m . . . . . m . . m . . m .
 m . . m . . m . . m . . 1 . . m . . m . . m . .
m . . m . . m . . m . 3 . 4 . m . . m . . m . . m
 . . m . . m . . m . . 2 . . m . . m . . m . . m
  . m . . m . . m . . . . . m . . m . . m . . m
   m . . m . . m . . m . . m . . m . . m . . m
    . . m . . m . . m . . m . . m . . m . . m
     . m . . m . . m . . m . . m . . m . . m
      m . . m . . m . . m . . m . . m . . m
       . . m . . m . . m . . m . . m . . m
        . m . . m . . m . . m . . m . . m
         m . . m . . m . . m . . m . . m
          . . m . . m . . m . . m . . m
           . m . . m . . m . . m . . m
            m . . m . . m . . m . . m
```

## Legend

- `.`: ground
- `1` to `4`: where players 1 to 4 start
- `m`: a wild monster, of a species rolled from the instance blueprint's list
