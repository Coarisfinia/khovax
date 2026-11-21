"""Makes the props' shared texture set (#1853) from CC0 textures: downloads each source (pinned by
its checksum), reduces it to TILE texels square and a few flat tones for the game's cel shading
(blurred a little, then each texel set to the mean colour of its brightness band, so the surface's
detail stays as flat areas rather than photo grain), and writes it to `textures/<name>.png`, where
every prop's script takes it from (lib/prop_paint.py). Run it again only to change the set; the
sources and their licence are in `textures/SOURCE.md`.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/prop_textures.py

Blender reads the JPEGs (the tooling has no image library of its own). Only the committed PNGs
are read by the model builds, so a build never downloads anything."""

import hashlib
import io
import os
import sys
import tempfile
import urllib.request
import zipfile

import bpy
import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "textures")
TILE = 512
# Texels the colour is blurred over before banding (wrapping round, so the tile still tiles).
BLUR = 2


class Source:
    def __init__(self, url, sha256, member=None, tones=5, saturation=1.0, brightness=1.0):
        self.url = url
        self.sha256 = sha256
        # The file inside a zip download, or None for a plain image.
        self.member = member
        self.tones = tones
        self.saturation = saturation
        self.brightness = brightness


# Every texture is CC0 (public domain): Poly Haven's and ambientCG's whole libraries are.
SET = {
    # Pale weathered rock with lichen spots, greyed a little toward the reference's stone.
    "stone": Source("https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_boulder_dry/rock_boulder_dry_diff_1k.jpg",
                    "20f653a42fb24f42aa40641663070d578678da49af18cc1049dbdd4ed8679f3c", saturation=0.45, brightness=0.85),
    # Sandstone blocks, for walls and floors.
    "sandstone": Source("https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/old_sandstone_02/old_sandstone_02_diff_1k.jpg",
                        "a58111224570bb33eba3c348bc7e3207255b5efb07f9cf274209c56b71d6825c"),
    # Weathered planks.
    "wood": Source("https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/brown_planks_09/brown_planks_09_diff_1k.jpg",
                   "6a890d75d48787518ccf32cb44e7557d1695e8a9180e813f79f7bfed075896ed"),
    # Moss, laid over any of them where faces point up.
    "moss": Source("https://ambientcg.com/get?file=Moss002_1K-JPG.zip",
                   "727d4e3134f604837c2e11aa3bf12417a022d3c668a6d7339efa572fdbb056bb",
                   member="Moss002_1K-JPG_Color.jpg", tones=4),
    # The handmade realm (#2460, #2484): pale, muted surfaces, so its colourful beasts stand out
    # (the owner, on #2484). A prop gives them a colour with `prop_paint.material`'s tint.
    # Creased sheet paper: pages, pop-up cliffs, shadow screens, the paper floor.
    "paper": Source("https://ambientcg.com/get?file=Paper003_1K-JPG.zip",
                    "90b44da4c960ba044b37c26713c50ef1986687a522f1bbe847aeb9b471409040",
                    member="Paper003_1K-JPG_Color.jpg", tones=4),
    # Thick folded card: pop-up cliffs, page drifts, the nest.
    "card": Source("https://ambientcg.com/get?file=Cardboard004_1K-JPG.zip",
                   "f427eb664e0cbc97fc1e7066a800f3ad656ad4eeaa0d0314182ea8b7f03e4a64",
                   member="Cardboard004_1K-JPG_Color.jpg", tones=4, saturation=0.55, brightness=1.1),
    # Woven bookcloth: book covers and spines.
    "bookcloth": Source("https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/book_pattern/book_pattern_col1_1k.jpg",
                        "30661c007bd43e5fda5c11a8edb49e0949e19b1b55fdbe3baf7139fb3a0f8a70",
                        tones=4, saturation=0.5, brightness=2.0),
    # Chunky knit, greyed to a cream: wound yarn, knitted fabric, the woollen floor.
    "yarn": Source("https://ambientcg.com/get?file=Fabric018_1K-JPG.zip",
                   "495f53bb0339963b6405e016435d59763de460e0e659a91a59cb8bc12a687b66",
                   member="Fabric018_1K-JPG_Color.jpg", tones=4, saturation=0.05, brightness=2.5),
    # Coarse hessian: cord and rope, kite sails, stage curtains, sandbags.
    "cloth": Source("https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/hessian_380/hessian_380_diff_1k.jpg",
                    "5727302df3a9c845e6320ff186ac13fc7d0f1ffcd6fda71667e808e09379fe6f",
                    tones=4, saturation=0.6, brightness=1.1),
    # A fine white weave: the stage's painted scenery flats, tinted with their paint.
    "canvas": Source("https://ambientcg.com/get?file=Fabric019_1K-JPG.zip",
                     "a6a9310516750214fc4e3e9e05269035d76670223c45d7810f3d89ad67b46562",
                     member="Fabric019_1K-JPG_Color.jpg", tones=4),
    # Tarnished brass: the orrery's gears, arms and pedestal, clasps.
    "brass": Source("https://ambientcg.com/get?file=Metal048C_1K-JPG.zip",
                    "c24d2f8b82d1ed5e876d6ceae4bedff76f32a5d565ecf21e2b370e56df61fb14",
                    member="Metal048C_1K-JPG_Color.jpg", tones=4, saturation=0.7),
    # Worn dark iron: needles, stage weights.
    "iron": Source("https://ambientcg.com/get?file=Metal015_1K-JPG.zip",
                   "76fec89bb8e04d97b90bbf9b47caf27476b7d226645e81bff9d8c8087f27f0db",
                   member="Metal015_1K-JPG_Color.jpg", tones=4, saturation=0.25, brightness=1.4),
    # Dry, wind-flattened grass: the Kite Ridge's floor.
    "windswept_grass": Source("https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/withered_grass/withered_grass_diff_1k.jpg",
                              "8bebfb639ef74f651bc445526c46c845beee52a86d831848b82eb2bbbf2d98ee",
                              saturation=0.6, brightness=1.2),
    # Pale floorboards: the Dusk Stage's boards.
    "stage_boards": Source("https://ambientcg.com/get?file=WoodFloor051_1K-JPG.zip",
                           "3f493484eab1ec5e1c466b90e515003b286fc6d7f84ff8ff6485900bfc26cef5",
                           member="WoodFloor051_1K-JPG_Color.jpg", saturation=0.7),
    # Riveted metal plates: the Orrery Plateau's floor.
    "metal_plates": Source("https://ambientcg.com/get?file=MetalPlates004_1K-JPG.zip",
                           "80dd04ac1a96d7280b34fc947b522c0e70e1eeae6c377aec5d1742a36be3139e",
                           member="MetalPlates004_1K-JPG_Color.jpg", tones=4, saturation=0.5, brightness=1.5),
}


def fetch(source):
    """The source image's bytes, after checking the download against its checksum."""
    request = urllib.request.Request(source.url, headers={"User-Agent": "khovax-prop-textures"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != source.sha256:
        raise SystemExit("checksum mismatch for %s: %s" % (source.url, digest))
    if source.member is not None:
        data = zipfile.ZipFile(io.BytesIO(data)).read(source.member)
    return data


def pixels(data):
    """The image's RGB as a (rows from the bottom, columns, 3) array, sRGB 0..1."""
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as handle:
        handle.write(data)
        path = handle.name
    try:
        image = bpy.data.images.load(path)
        image.colorspace_settings.name = "sRGB"
        flat = numpy.empty(image.size[0] * image.size[1] * 4, dtype=numpy.float32)
        image.pixels.foreach_get(flat)
        out = flat.reshape(image.size[1], image.size[0], 4)[..., :3].astype(float)
        bpy.data.images.remove(image)
    finally:
        os.unlink(path)
    return out


def reduce(rgb, source):
    """TILE texels square, blurred, graded and banded into `source.tones` flat tones."""
    step = rgb.shape[0] // TILE
    small = rgb.reshape(TILE, step, TILE, step, 3).mean(axis=(1, 3))
    for axis in (0, 1):
        small = sum(numpy.roll(small, shift, axis=axis) for shift in range(-BLUR, BLUR + 1)) / (2 * BLUR + 1)
    grey = small.mean(axis=2, keepdims=True)
    small = numpy.clip((grey + (small - grey) * source.saturation) * source.brightness, 0.0, 1.0)
    light = small @ numpy.array([0.2126, 0.7152, 0.0722])
    edges = numpy.quantile(light, numpy.linspace(0.0, 1.0, source.tones + 1)[1:-1])
    band = numpy.searchsorted(edges, light)
    out = numpy.empty_like(small)
    for tone in range(source.tones):
        out[band == tone] = small[band == tone].mean(axis=0)
    return out


def write(name, rgb):
    rgba = numpy.ones((TILE, TILE, 4), dtype=numpy.float32)
    rgba[..., :3] = rgb
    image = bpy.data.images.new(name, TILE, TILE, alpha=False)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = os.path.join(OUT, name + ".png")
    image.file_format = "PNG"
    image.save()
    print("TEXTURE", name, image.filepath_raw)


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(SET)
    for name in names:
        write(name, reduce(pixels(fetch(SET[name])), SET[name]))


main()
