"""Makes the props' shared texture set (#1853) from CC0 textures: downloads each source (pinned by
its checksum), reduces it to TILE texels square and a few flat tones for the game's cel shading
(blurred a little, then each texel set to the mean colour of its brightness band, so the surface's
detail stays as flat areas rather than photo grain), and writes it to `textures/<name>.png`, where
every prop's script takes it from (lib/prop_paint.py). Run it again only to change the set; the
sources and their licence are in `textures/SOURCE.md`.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/prop_textures.py

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
