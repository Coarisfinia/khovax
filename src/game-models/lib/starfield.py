"""Our own starry sky as a texture (#1635), drawn from a fixed seed so it rebuilds byte for byte.

Generated stars read as fake when every one is drawn differently (a star with five points beside
one with seven), so every star here is one of two fixed shapes, drawn the same way each time: a
soft round dot, or, for the few brightest, a sparkle with exactly four points. Their brightness
falls off steeply (most are faint, a few bright), their size follows it, and each takes one of a
few faint tints. Behind them lies a soft, deep gradient with a faint band of haze.

The texture is an equirectangular panorama: a texel's column is its longitude and its row its
latitude, and each star is drawn in the angles around its own centre, so it keeps its shape away
from the equator and nothing breaks where the columns wrap. `lonlat` gives the angles a direction
from a body's middle has in it (longitude 0 faces the model's front, -Y; the seam is behind, at
+Y): a model maps its surface with them, as `uv` does.

Only + - * / and square roots run per texel (exact in IEEE arithmetic on every machine); the few
sines and cosines are taken once per row and column with Python's `math`, and the stars come
from Python's own seeded generator, so a build on another CPU gives the same bytes.
"""

import math
import random

import numpy

# The background: deep blue below to a deep violet above, and a faint violet haze along a band
# tilted across the sky. Colours are sRGB, as an 8-bit texture stores them.
DEEP = numpy.array((0.010, 0.014, 0.050))
HIGH = numpy.array((0.060, 0.030, 0.120))
HAZE = numpy.array((0.140, 0.100, 0.220))
# The haze band's great circle (its normal, in the texture's frame: see Sky) and its half width,
# as the sine of an angle.
HAZE_NORMAL = (0.35, 0.20, 0.915)
HAZE_WIDTH = 0.28

# A star's tint: mostly white, some pale blue and some pale gold (their shares add up to 1).
TINTS = (
    ((1.00, 1.00, 1.00), 0.55),
    ((0.78, 0.88, 1.00), 0.30),
    ((1.00, 0.90, 0.70), 0.15),
)


def lonlat(x, y, z):
    """The longitude and latitude, in radians, of the direction (x, y, z) in the model's space
    (Blender's: Z up, the front -Y). Longitude 0 faces the front and grows toward +X."""
    return math.atan2(x, -y), math.atan2(z, math.hypot(x, y))


def uv(x, y, z):
    """Where the direction (x, y, z) lies on the texture (u from 0 to 1 around, v from 0 at the
    bottom to 1 at the top)."""
    lon, lat = lonlat(x, y, z)
    return (lon + math.pi) / (2.0 * math.pi), (lat + math.pi / 2.0) / math.pi


class Sky:
    """A `width` by `height` panorama (rows from the bottom, as Blender's pixels run), RGB."""

    def __init__(self, width, height):
        self.width, self.height = width, height
        self.lons = [2.0 * math.pi * (column + 0.5) / width - math.pi for column in range(width)]
        self.lats = [math.pi * (row + 0.5) / height - math.pi / 2.0 for row in range(height)]
        cos_lon = numpy.array([math.cos(lon) for lon in self.lons])
        sin_lon = numpy.array([math.sin(lon) for lon in self.lons])
        cos_lat = numpy.array([math.cos(lat) for lat in self.lats])
        sin_lat = numpy.array([math.sin(lat) for lat in self.lats])
        # Every texel's direction on the unit sphere, in the texture's own frame (x toward
        # longitude 0, y toward longitude 90 degrees, z up): the model's frame turned about its
        # up axis (`lonlat`: longitude 0 is the model's front, -Y), so every star and the haze are
        # placed and drawn by longitude and latitude alike, and keep their shapes on the model.
        self.x = numpy.outer(cos_lat, cos_lon)
        self.y = numpy.outer(cos_lat, sin_lon)
        self.z = numpy.outer(sin_lat, numpy.ones(width))
        self.pixels = numpy.zeros((height, width, 3))

    def background(self):
        """The deep gradient from bottom to top, and the haze band across it."""
        rise = (self.z + 1.0) / 2.0
        rise = rise * rise * (3.0 - 2.0 * rise)
        self.pixels = DEEP + (HIGH - DEEP) * rise[..., None]
        nx, ny, nz = HAZE_NORMAL
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        off = (self.x * nx + self.y * ny + self.z * nz) / length / HAZE_WIDTH
        band = numpy.clip(1.0 - off * off, 0.0, 1.0)
        self.pixels = self.pixels + HAZE * (band * band)[..., None]

    def stamp(self, lon, lat, reach, shape, colour):
        """Adds `colour` times `shape(east, north)` around (lon, lat), where east and north are a
        texel's offsets from it in radians along the sphere; only texels within `reach` radians."""
        cos_lat0, sin_lat0 = math.cos(lat), math.sin(lat)
        cos_lon0, sin_lon0 = math.cos(lon), math.sin(lon)
        # The star's direction and the east and north directions at it.
        centre = (cos_lat0 * cos_lon0, cos_lat0 * sin_lon0, sin_lat0)
        east = (-sin_lon0, cos_lon0, 0.0)
        north = (-sin_lat0 * cos_lon0, -sin_lat0 * sin_lon0, cos_lat0)
        rows = [row for row in range(self.height) if abs(self.lats[row] - lat) <= reach]
        across = reach / max(cos_lat0, 0.05)
        columns = sorted({round((lon + math.pi) / (2.0 * math.pi) * self.width - 0.5 + step) % self.width
                          for step in range(-math.ceil(across / (2.0 * math.pi) * self.width) - 1,
                                            math.ceil(across / (2.0 * math.pi) * self.width) + 2)})
        if not rows or not columns:
            return
        grid = numpy.ix_(rows, columns)
        x, y, z = self.x[grid], self.y[grid], self.z[grid]
        facing = x * centre[0] + y * centre[1] + z * centre[2]
        # The texel's offset in the tangent plane, which is its angle away for these small reaches.
        e = x * east[0] + y * east[1] + z * east[2]
        n = x * north[0] + y * north[1] + z * north[2]
        light = numpy.where(facing > 0.0, shape(e, n), 0.0)
        self.pixels[grid] = self.pixels[grid] + numpy.asarray(colour) * light[..., None]

    def image(self):
        """The panorama as RGBA rows from the bottom, clamped to 0..1."""
        rgba = numpy.ones((self.height, self.width, 4))
        rgba[..., :3] = numpy.clip(self.pixels, 0.0, 1.0)
        return rgba


def dot(radius):
    """A soft round dot `radius` radians across its half: bright in the middle, fading to nothing."""

    def shape(e, n):
        fall = numpy.clip(1.0 - (e * e + n * n) / (radius * radius), 0.0, 1.0)
        return fall * fall

    return shape


def disc(radius, edge):
    """A flat round disc `radius` radians across its half, its rim fading over `edge`: a painted
    spot such as a glowing eye, not a star."""

    def shape(e, n):
        return numpy.clip((radius - numpy.sqrt(e * e + n * n)) / edge, 0.0, 1.0)

    return shape


def sparkle(radius, ray, width):
    """A dot with exactly four points: thin rays `ray` radians long along east, west, north and
    south, `width` radians across at their root and narrowing to a point."""
    core = dot(radius)

    def arm(along, across):
        left = numpy.clip(1.0 - numpy.abs(along) / ray, 0.0, 1.0)
        half = width * left
        side = numpy.clip(1.0 - (across * across) / numpy.maximum(half * half, 1e-12), 0.0, 1.0)
        return left * left * side

    def shape(e, n):
        return numpy.maximum(core(e, n), numpy.maximum(arm(e, n), arm(n, e)))

    return shape


def stars(sky, seed, count, smallest, largest, sparkles, ray, polar):
    """Draws `count` stars on `sky` from `seed`, spread evenly over the sphere within `polar` of
    the equator (as a sine of latitude). Brightness falls off as a power (most faint), the radius
    grows with it from `smallest` to `largest`, and the `sparkles` brightest are four-pointed with
    rays `ray` long; the rest are dots."""
    rolls = random.Random(seed)
    drawn = []
    for _ in range(count):
        height = (2.0 * rolls.random() - 1.0) * polar
        lon = 2.0 * math.pi * rolls.random() - math.pi
        brightness = 0.25 + 0.75 * rolls.random() ** 4
        pick, share = rolls.random(), 0.0
        for tint, weight in TINTS:
            share += weight
            if pick <= share:
                break
        drawn.append((brightness, lon, math.asin(height), tint))
    drawn.sort(key=lambda star: -star[0])
    for rank, (brightness, lon, lat, tint) in enumerate(drawn):
        radius = smallest + (largest - smallest) * brightness
        colour = [channel * brightness for channel in tint]
        if rank < sparkles:
            sky.stamp(lon, lat, ray, sparkle(radius, ray, radius * 0.45), colour)
        else:
            sky.stamp(lon, lat, radius, dot(radius), colour)
