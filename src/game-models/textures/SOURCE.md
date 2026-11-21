# Props' shared texture set

The textures every world prop paints itself from (#1853, `../lib/prop_paint.py`). Each is a CC0
texture, downloaded at 1K, checked against its checksum and reduced to 512 texels square and a few
flat tones by `../prop_textures.py`, which lists the exact files, their checksums and the grading
of each (the handmade realm's are paled, so its beasts stand out, #2484).

- **Author:** Poly Haven (stone, sandstone, wood, bookcloth, cloth, windswept_grass) and ambientCG
  (moss, paper, card, yarn, canvas, brass, iron, stage_boards, metal_plates); reduced by the project
- **Source:**
  - `stone.png`: Poly Haven, "Rock Boulder Dry", https://polyhaven.com/a/rock_boulder_dry
  - `sandstone.png`: Poly Haven, "Old Sandstone 02", https://polyhaven.com/a/old_sandstone_02
  - `wood.png`: Poly Haven, "Brown Planks 09", https://polyhaven.com/a/brown_planks_09
  - `moss.png`: ambientCG, "Moss 002", https://ambientcg.com/view?id=Moss002
  - `paper.png`: ambientCG, "Paper 003", https://ambientcg.com/view?id=Paper003
  - `card.png`: ambientCG, "Cardboard 004", https://ambientcg.com/view?id=Cardboard004
  - `bookcloth.png`: Poly Haven, "Book Pattern" (its first colour, `col1`), https://polyhaven.com/a/book_pattern
  - `yarn.png`: ambientCG, "Fabric 018", https://ambientcg.com/view?id=Fabric018
  - `cloth.png`: Poly Haven, "Hessian 380", https://polyhaven.com/a/hessian_380
  - `canvas.png`: ambientCG, "Fabric 019", https://ambientcg.com/view?id=Fabric019
  - `brass.png`: ambientCG, "Metal 048 C", https://ambientcg.com/view?id=Metal048C
  - `iron.png`: ambientCG, "Metal 015", https://ambientcg.com/view?id=Metal015
  - `windswept_grass.png`: Poly Haven, "Withered Grass", https://polyhaven.com/a/withered_grass
  - `stage_boards.png`: ambientCG, "Wood Floor 051", https://ambientcg.com/view?id=WoodFloor051
  - `metal_plates.png`: ambientCG, "Metal Plates 004", https://ambientcg.com/view?id=MetalPlates004
- **License:** CC0 1.0, see `LICENSE.md` next to this file. Credit is welcome, not required.
- **Checked:** 2026-11-21, for the handmade realm's eleven (#2484): each Poly Haven page states
  "CC0 1.0 Universal - public domain dedication", each ambientCG page that its assets are under
  the Creative Commons CC0 license.
