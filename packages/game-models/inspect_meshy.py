"""One compact report on a generated model's download (#1523), so an agent reads one screen
instead of measuring the mesh by hand before import_source.py and the model script:

    uv run --locked packages/game-models/inspect_meshy.py <download.glb>

It starts Blender itself (through blender.py) and prints only the report:
- **file:** its size, the glTF's generator and whether it carries AI-generation markers (a
  generator, copyright or `extras` naming them, or metadata inside its images);
- **mesh:** triangles, vertices and how many of them are seam splits, UV islands, custom normals,
  node rotations, the bounds and where the origin sits against the soles;
- **material:** `doubleSided`, the alpha mode and each texture's kind, size and format;
- **eyes:** glowing spots painted on the base colour (bright and saturated), found on the surface
  and grouped where they sit;
- **body:** the separate columns that horizontal slices cut near the ground (legs, a stalk, a
  belly), and a profile of slices along its length (their height range and half width), as
  candidate joint positions;
- **rig:** if the download carries one, each chain (bones from a fork or the root to the next fork
  or an end), its bone count and what it moves (the vertices it weighs most, their centroid and
  height range). It flags a chain whose vertices reach far past its bones (a part without a full
  chain, like a stub under a whole stalk) and two chains whose weights mix far from where they
  fork (one stalk dragging another, #1519).

Coordinates are Blender's, as the model scripts use them: Z up, the game's front is -Y, in the
download's own units.
"""

import itertools
import json
import os
import struct
import subprocess
import sys

try:
    import bpy
    import numpy as np  # Blender's own
except ImportError:  # outside Blender: main() starts it with this script
    bpy = np = None

HERE = os.path.dirname(os.path.abspath(__file__))
# Report lines carry this prefix inside Blender, so the outer run can drop Blender's own output.
PREFIX = "INSPECT| "

# A painted eye's colour: bright and saturated, like the glowing eyes the generator paints.
EYE_VALUE, EYE_SATURATION = 0.75, 0.3
# The share of the surface's samples that may be eye-coloured before it reads as the body's own
# colour (a glowing creature) rather than eyes.
EYE_SHARE = 0.03
# Grid cells a model's longest side is cut into, to group the eye samples into spots.
CELLS = 48
# Heights (a share of the model's height) the column slices cut at, and how many lengthwise slices
# the profile takes.
COLUMN_HEIGHTS = (0.05, 0.15, 0.3)
PROFILE_SLICES = 9
# A chain's vertices "reach past" it when they lie farther from its bones than this share of the
# model's height, at their 90th percentile.
REACH = 0.12
# Two chains "bleed" into each other when at least this share of the vertices the smaller one weighs
# BLEED_WEIGHT or more carry that much of both, farther than REACH from both chains' starts (next to
# a fork, mixed weights only smooth the joint), and at least BLEED_VERTICES of them.
BLEED, BLEED_WEIGHT, BLEED_VERTICES = 0.2, 0.1, 20
# How long (seconds) Blender may take before the report gives up on it: far above a large download's.
TIMEOUT = 300


# What the report finds left to do, printed last as its verdict.
NEXT = []


def out(line=""):
    print(PREFIX + line)


def num(value):
    """A coordinate to two places, without a "-0.00"."""
    return "%.2f" % (round(float(value), 2) + 0.0)


def fmt(vector):
    return "(" + ", ".join(num(value) for value in vector) + ")"


# --- The file: read straight from the glTF, as the download carries it -------------------------


def read_glb(path):
    with open(path, "rb") as stream:
        data = stream.read()
    if len(data) < 20 or data[:4] != b"glTF":
        sys.exit("not a binary glTF: %s" % path)
    offset, gltf, binary = 12, None, b""
    while offset + 8 <= len(data):
        size, kind = struct.unpack_from("<I4s", data, offset)
        if offset + 8 + size > len(data):
            sys.exit("truncated glTF: %s" % path)
        chunk = data[offset + 8:offset + 8 + size]
        if kind == b"JSON":
            gltf = json.loads(chunk)
        elif kind == b"BIN\x00":
            binary = chunk
        offset += 8 + size
    if gltf is None:
        sys.exit("no JSON chunk: %s" % path)
    # A download is one self-contained file: a path to another file would have the importer read
    # whatever it names on this machine.
    if any("uri" in item for item in gltf.get("images", []) + gltf.get("buffers", [])):
        sys.exit("refused: %s points to external files" % path)
    return gltf, binary, len(data)


def image_bytes(gltf, binary, index):
    if index is None:  # a texture whose source sits in an extension (WebP, Basis)
        return None
    image = gltf["images"][index]
    if "bufferView" not in image:
        return None
    view = gltf["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    return binary[start:start + view["byteLength"]]


def image_info(data):
    """The image's format, size and the metadata blocks it carries (EXIF, XMP, C2PA, comments)."""
    if data is None:
        return "not embedded", None, []
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        width, height = struct.unpack_from(">II", data, 16)
        meta, offset = [], 8
        while offset + 8 <= len(data):
            size, kind = struct.unpack_from(">I4s", data, offset)
            if kind in (b"tEXt", b"iTXt", b"zTXt", b"eXIf", b"caBX"):
                meta.append(kind.decode())
            offset += 12 + size
        return "PNG", (width, height), meta
    if data[:2] == b"\xff\xd8":
        size, meta, offset = None, [], 2
        while offset + 4 <= len(data) and data[offset] == 0xFF:
            marker = data[offset + 1]
            length = struct.unpack_from(">H", data, offset + 2)[0]
            body = data[offset + 4:offset + 2 + length]
            if marker == 0xE1:
                meta.append("XMP" if body.startswith(b"http://ns.adobe.com") else "EXIF")
            elif marker == 0xEB:
                meta.append("C2PA")
            elif marker == 0xFE:
                meta.append("comment")
            elif marker in (0xC0, 0xC1, 0xC2):
                height, width = struct.unpack_from(">HH", data, offset + 5)
                size = (width, height)
                break
            offset += 2 + length
        return "JPEG", size, meta
    return "unknown", None, []


# Words that mark a text as an AI-generation marker.
MARKER_WORDS = ("meshy", " ai", "ai-", "generated", "generator", "c2pa", "trainedalgorithmic")


def marked(text):
    return any(word in " " + text.lower() for word in MARKER_WORDS)


def marked_extras(node):
    """Whether any `extras` in the glTF names AI generation."""
    if isinstance(node, dict):
        return ("extras" in node and marked(json.dumps(node["extras"]))) or any(
            marked_extras(value) for value in node.values())
    if isinstance(node, list):
        return any(marked_extras(value) for value in node)
    return False


def report_file(path, gltf, binary, size):
    asset = gltf.get("asset", {})
    out("%s: %.1f MB, generator %r" % (os.path.basename(path), size / 1e6, asset.get("generator", "none")))
    markers = []
    for key in ("generator", "copyright"):
        if key in asset and marked(str(asset[key])):
            markers.append("asset.%s" % key)
    if marked_extras(gltf):
        markers.append("extras")
    for index in range(len(gltf.get("images", []))):
        meta = image_info(image_bytes(gltf, binary, index))[2]
        markers += ["image %d %s" % (index, kind) for kind in meta]
    if markers:
        NEXT.append("keep the AI markers (%s)" % ", ".join(markers))
    out("MARKERS  " + (", ".join(markers) + ": keep them" if markers else "none (generator, extras, image metadata)"))


def report_materials(gltf, binary):
    textures = gltf.get("textures", [])
    for number, material in enumerate(gltf.get("materials", [])):
        pbr = material.get("pbrMetallicRoughness", {})
        slots = [("base", pbr.get("baseColorTexture")), ("metal-rough", pbr.get("metallicRoughnessTexture")),
                 ("normal", material.get("normalTexture")), ("occlusion", material.get("occlusionTexture")),
                 ("emissive", material.get("emissiveTexture"))]
        # Anything beyond an opaque, single-sided base colour of at most 1024 is for import_source.py.
        parts = []
        strip = (material.get("doubleSided", False) or material.get("alphaMode", "OPAQUE") != "OPAQUE"
                 or any(slot for _kind, slot in slots[1:]))
        for kind, slot in slots:
            if slot is None:
                continue
            texture = textures[slot["index"]]
            source = texture.get("source")
            for name in ("KHR_texture_basisu", "EXT_texture_webp"):  # only an extension holds the image
                if source is None:
                    source = texture.get("extensions", {}).get(name, {}).get("source")
            form, dims, _meta = image_info(image_bytes(gltf, binary, source))
            parts.append("%s %s %s" % (kind, "%dx%d" % dims if dims else "?", form))
            if dims is None:
                NEXT.append("check the %s texture's size by hand: its format isn't read here" % kind)
            strip = strip or (kind == "base" and dims is not None and max(dims) > 1024)
        out("MATERIAL %s: doubleSided %s, alpha %s; %s" % (
            material.get("name", number), material.get("doubleSided", False), material.get("alphaMode", "OPAQUE"),
            ", ".join(parts) or "no textures"))
        if strip:
            NEXT.append("import_source.py: base colour only, at 1024, single-sided, opaque, matte")
    if not gltf.get("materials"):
        out("MATERIAL none: an untextured shape")
        NEXT.append("untextured: ask for the textured download")


# --- The mesh, the eyes, the body and the rig: read through Blender's importer -----------------


def grid_groups(points, cell):
    """Groups points that lie in touching grid cells; returns lists of point indices, largest
    first."""
    cells = {}
    for index, key in enumerate(map(tuple, np.floor(points / cell).astype(np.int64))):
        cells.setdefault(key, []).append(index)
    groups = Groups()
    for key in cells:
        for step in itertools.product((-1, 0, 1), repeat=3):
            near = tuple(k + s for k, s in zip(key, step))
            if near in cells:
                groups.join(key, near)
    found = [sum((cells[key] for key in members), []) for members in groups.members(cells)]
    return sorted(found, key=len, reverse=True)


def slice_pieces(positions, triangles, axis, value):
    """The pieces the plane `axis` = `value` cuts through the mesh, each as the points where its
    edges cross the plane: a loop follows the faces from one crossing edge to the next, and loops
    whose outlines overlap (a wall's two sides, a hole) are one piece."""
    value += 1e-7  # off any vertex lying exactly on the plane
    pairs = np.sort(triangles[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 3, 2), axis=2)
    edges, index = np.unique(pairs.reshape(-1, 2), axis=0, return_inverse=True)
    index = index.reshape(-1, 3)
    a, b = positions[edges[:, 0]], positions[edges[:, 1]]
    crossing = (a[:, axis] - value) * (b[:, axis] - value) < 0
    share = np.where(crossing, (value - a[:, axis]) / np.where(crossing, b[:, axis] - a[:, axis], 1.0), 0.0)
    points = a + (b - a) * share[:, None]
    groups = Groups()
    for triangle in index[crossing[index].sum(axis=1) >= 2]:
        cut = [edge for edge in triangle if crossing[edge]]
        groups.join(cut[0], cut[1])
    loops = groups.members(np.flatnonzero(crossing))
    other = [k for k in range(3) if k != axis]
    boxes = [(points[loop][:, other].min(axis=0), points[loop][:, other].max(axis=0)) for loop in loops]
    merged = Groups()
    for i, (low_i, high_i) in enumerate(boxes):
        for j in range(i):
            if (boxes[j][0] <= high_i).all() and (low_i <= boxes[j][1]).all():
                merged.join(i, j)
    pieces = merged.members(range(len(loops)))
    return [points[np.concatenate([loops[i] for i in piece])] for piece in pieces]


class Groups:
    """Union-find over any hashable items."""

    def __init__(self):
        self.parent = {}

    def find(self, item):
        self.parent.setdefault(item, item)
        while self.parent[item] != item:
            self.parent[item] = self.parent[self.parent[item]]
            item = self.parent[item]
        return item

    def join(self, a, b):
        self.parent[self.find(a)] = self.find(b)

    def members(self, items):
        found = {}
        for item in items:
            found.setdefault(self.find(item), []).append(item)
        return list(found.values())


def scene_mesh():
    # The importer adds a shape to draw the bones with: not part of the download's mesh.
    shapes = {bone.custom_shape for obj in bpy.context.scene.objects if obj.type == "ARMATURE" for bone in obj.pose.bones}
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj not in shapes]
    if not meshes:
        sys.exit("no mesh in the download")
    largest = max(meshes, key=lambda obj: len(obj.data.vertices))
    if len(meshes) > 1:
        # One mesh to report on, with every part's vertices, materials and weights.
        out("MESH     %d meshes, joined into one for this report" % len(meshes))
        with bpy.context.temp_override(active_object=largest, selected_editable_objects=meshes):
            bpy.ops.object.join()
    return largest


def report_mesh(gltf, mesh):
    data = mesh.data
    count = len(data.vertices)
    flat = np.empty(count * 3, dtype=np.float64)
    data.vertices.foreach_get("co", flat)
    local = flat.reshape(-1, 3)
    matrix = np.array(mesh.matrix_world)
    positions = local @ matrix[:3, :3].T + matrix[:3, 3]
    triangles = sum(len(polygon.vertices) - 2 for polygon in data.polygons)
    normals = any("NORMAL" in primitive["attributes"] for item in gltf.get("meshes", [])
                  for primitive in item["primitives"])
    welded = len(np.unique(np.round(positions, 6), axis=0))
    islands = uv_islands(data)
    rotated = [node.get("name", str(index)) for index, node in enumerate(gltf.get("nodes", []))
               if "mesh" in node and (any(abs(v) > 1e-6 for v in node.get("rotation", [0, 0, 0, 1])[:3])
                                      or _matrix_turns(node.get("matrix")))]
    out("MESH     %d triangles, %d vertices (%d seam splits), %s UV islands, custom normals %s, mesh nodes "
        "rotated: %s" % (triangles, count, count - welded, islands, "yes" if normals else "no",
                         ", ".join(rotated) or "none"))
    low, high = positions.min(axis=0), positions.max(axis=0)
    size = high - low
    centre = (low + high) / 2
    out("BOUNDS   x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  (%.2f wide, %.2f long, %.2f tall)" % (
        low[0], high[0], low[1], high[1], low[2], high[2], size[0], size[1], size[2]))
    # The download's origin is its scene's: the positions are in the scene's space.
    origin = np.zeros(3)
    out("ORIGIN   %s above the soles, %s off centre in x, %s in y%s" % (
        num(origin[2] - low[2]), num(origin[0] - centre[0]), num(origin[1] - centre[1]),
        "" if abs(origin[2] - low[2]) < 0.01 * size[2] else ": not on its feet"))
    if abs(origin[2] - low[2]) >= 0.01 * size[2]:
        NEXT.append("place it: origin to the soles (z %s), between the feet" % num(low[2]))
    if size[2] < max(size[0], size[1]) * 0.25:
        out("         flat in z: check the up axis")
    return positions, low, high


def _matrix_turns(matrix):
    if not matrix:
        return False
    # glTF's matrices are column-major: each of the first three columns is an axis, scaled.
    axes = [matrix[i * 4:i * 4 + 3] for i in range(3)]
    for i, axis in enumerate(axes):
        length = sum(value * value for value in axis) ** 0.5 or 1.0
        if any(abs(axis[j] / length - (1.0 if i == j else 0.0)) > 1e-6 for j in range(3)):
            return True
    return False


def uv_islands(data):
    if not data.uv_layers:
        return "no"
    uvs = data.uv_layers.active.data
    # Faces sharing a vertex at the same UV belong to one island; a seam gives the same spot two UVs.
    groups = Groups()
    for polygon in data.polygons:
        corners = [(data.loops[loop].vertex_index, round(uvs[loop].uv[0], 5), round(uvs[loop].uv[1], 5))
                   for loop in polygon.loop_indices]
        for corner in corners:
            groups.join(corner, corners[0])
    return len(groups.members(list(groups.parent)))


def base_pixels(material):
    """The material's base colour texture as a (height, width, 3) array, or None."""
    if material is None or not material.node_tree:
        return None
    shader = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if shader is None or not shader.inputs["Base Color"].links:
        return None
    node = shader.inputs["Base Color"].links[0].from_node
    if node.type != "TEX_IMAGE" or node.image is None:
        return None
    width, height = node.image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    node.image.pixels.foreach_get(pixels)
    return pixels.reshape(height, width, 4)[:, :, :3]


def report_eyes(mesh, positions, low, high):
    """Samples the base colour across every triangle, keeps the bright saturated samples and groups
    them where they sit."""
    data = mesh.data
    images = [base_pixels(material) for material in data.materials]
    if not data.uv_layers or all(image is None for image in images):
        out("EYES     no base colour texture to search")
        return
    data.calc_loop_triangles()
    loops = np.empty(len(data.loop_triangles) * 3, dtype=np.int64)
    data.loop_triangles.foreach_get("loops", loops)
    corner_vertex = np.empty(len(data.loops), dtype=np.int64)
    data.loops.foreach_get("vertex_index", corner_vertex)
    uv = np.empty(len(data.loops) * 2, dtype=np.float64)
    data.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    loops = loops.reshape(-1, 3)
    slots = np.empty(len(data.loop_triangles), dtype=np.int64)
    data.loop_triangles.foreach_get("material_index", slots)
    # Barycentric points over each triangle, fine enough to land on a painted spot smaller than it.
    steps = 6
    weights = np.array([(i, j, steps - i - j) for i in range(steps + 1) for j in range(steps + 1 - i)],
                       dtype=np.float64) / steps
    # Each triangle samples its own material's texture.
    sample_pos, colour = [], []
    for slot, pixels in enumerate(images):
        mine = slots == slot
        if pixels is None or not mine.any():
            continue
        height, width = pixels.shape[:2]
        sample_uv = np.einsum("ws,tsk->twk", weights, uv[loops[mine]]).reshape(-1, 2)
        sample_pos.append(np.einsum("ws,tsk->twk", weights, positions[corner_vertex[loops[mine]]]).reshape(-1, 3))
        x = np.clip((sample_uv[:, 0] % 1.0) * width, 0, width - 1).astype(np.int64)
        y = np.clip((sample_uv[:, 1] % 1.0) * height, 0, height - 1).astype(np.int64)
        colour.append(pixels[y, x])
    if not colour:
        out("EYES     no textured faces to search")
        return
    sample_pos, colour = np.concatenate(sample_pos), np.concatenate(colour)
    value = colour.max(axis=1)
    saturation = (value - colour.min(axis=1)) / np.maximum(value, 1e-6)
    glowing = (value >= EYE_VALUE) & (saturation >= EYE_SATURATION)
    share = glowing.mean()
    if share == 0:
        out("EYES     no glowing spots on the base colour: eyes aren't painted, or not bright")
        NEXT.append("find the eyes on a render: the colour search found none")
        return
    if share > EYE_SHARE:
        out("EYES     %.0f%% of the surface is bright and saturated: the body's own colour, no eye spots" % (share * 100))
        return
    points, found = sample_pos[glowing], colour[glowing]
    cell = (high - low).max() / CELLS
    groups = [group for group in grid_groups(points, cell) if len(group) >= 0.02 * len(points)]
    spots = []
    for group in groups[:6]:
        tone = found[group].mean(axis=0)
        spots.append("%s #%02x%02x%02x %.2f wide" % (
            fmt(points[group].mean(axis=0)), *(int(min(1.0, c) * 255) for c in tone),
            np.ptp(points[group], axis=0).max()))
    out("EYES     %d glowing spot%s: %s" % (len(spots), "" if len(spots) == 1 else "s", "; ".join(spots)))


def report_body(mesh, positions, low, high):
    mesh.data.calc_loop_triangles()
    triangles = np.empty(len(mesh.data.loop_triangles) * 3, dtype=np.int64)
    mesh.data.loop_triangles.foreach_get("vertices", triangles)
    triangles = triangles.reshape(-1, 3)
    size = high - low
    for share in COLUMN_HEIGHTS:
        z = low[2] + size[2] * share
        pieces = sorted(slice_pieces(positions, triangles, 2, z), key=lambda p: (round(p[:, 1].mean(), 1), p[:, 0].mean()))
        parts = ["%s %s" % (fmt((p[:, :2].min(axis=0) + p[:, :2].max(axis=0)) / 2), num(np.ptp(p[:, :2], axis=0).max()))
                 for p in pieces]
        out("COLUMNS  z %s: %d: %s" % (num(z), len(pieces), "  ".join(parts)))
    out("PROFILE  across its length, from -Y (front) to +Y: the height range at x=0 and the half width")
    for index in range(PROFILE_SLICES):
        y = low[1] + size[1] * (index + 0.5) / PROFILE_SLICES
        pieces = slice_pieces(positions, triangles, 1, y)
        if not pieces:
            continue
        points = np.concatenate(pieces)
        middle = points[np.abs(points[:, 0]) <= size[0] * 0.05]
        span = "z %s..%s" % (num(middle[:, 2].min()), num(middle[:, 2].max())) if len(middle) else "nothing at x=0"
        out("         y %s: %s, half width %s%s" % (num(y), span, num(np.abs(points[:, 0]).max()),
                                                  "" if len(pieces) == 1 else ", %d pieces" % len(pieces)))


def chains(armature):
    """The bones cut into chains: from a root or a fork's child, through single children, to the next
    fork or an end."""
    found = []
    starts = [bone for bone in armature.data.bones if bone.parent is None]
    while starts:
        bone = starts.pop(0)
        chain = [bone]
        while len(chain[-1].children) == 1:
            chain.append(chain[-1].children[0])
        found.append(chain)
        starts += list(chain[-1].children)
    return found


def segment_distance(points, heads, tails):
    """Each point's distance to the nearest of the segments head-tail."""
    best = np.full(len(points), np.inf)
    for head, tail in zip(heads, tails):
        axis = tail - head
        length = max(float(axis @ axis), 1e-12)
        share = np.clip((points - head) @ axis / length, 0.0, 1.0)
        best = np.minimum(best, np.linalg.norm(points - (head + share[:, None] * axis), axis=1))
    return best


def report_rig(mesh, positions, low, high):
    armature = next((obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"), None)
    if armature is None:
        out("RIG      none")
        NEXT.append("no rig: ask for Meshy's auto-rig, or rig it from the columns and profile")
        return
    world = armature.matrix_world
    groups = {group.index: group.name for group in mesh.vertex_groups}
    found = chains(armature)
    names = {bone.name: number for number, chain in enumerate(found) for bone in chain}
    weight = np.zeros((len(positions), len(found)))
    for vertex in mesh.data.vertices:
        for item in vertex.groups:
            chain = names.get(groups.get(item.group))
            if chain is not None:
                weight[vertex.index, chain] += item.weight
    weighted = weight.sum(axis=1) > 0
    owner = np.where(weighted, weight.argmax(axis=1), -1)
    segments = [(np.array([world @ bone.head_local for bone in chain]), np.array([world @ bone.tail_local for bone in chain]))
                for chain in found]
    near = np.stack([segment_distance(positions, *segment) for segment in segments], axis=1)
    tall = high[2] - low[2]
    out("RIG      %s: %d bones in %d chains, %d of %d vertices weighted, %s" % (
        armature.name, len(armature.data.bones), len(found), weighted.sum(), len(positions),
        "no clips" if not bpy.data.actions else "%d clips" % len(bpy.data.actions)))
    out("  chain                      bones  bones z    moves  centroid             z range     flag")
    strong = weight >= BLEED_WEIGHT
    away = np.stack([np.linalg.norm(positions - heads[0], axis=1) > REACH * tall for heads, _tails in segments], axis=1)
    flagged = 0
    for number, chain in enumerate(found):
        mine = owner == number
        heads, tails = segments[number]
        label = chain[0].name if len(chain) == 1 else "%s..%s" % (chain[0].name, chain[-1].name)
        span = "%.2f..%.2f" % (min(heads[:, 2].min(), tails[:, 2].min()), max(heads[:, 2].max(), tails[:, 2].max()))
        if not mine.any():
            out("  %-26s %5d  %-10s %5d" % (label, len(chain), span, 0))
            continue
        points = positions[mine]
        flags = []
        reach = np.percentile(near[mine, number], 90)
        if reach > REACH * tall:
            flags.append("REACHES %.2f past its bones" % reach)
        for other in range(len(found)):
            if other == number:
                continue
            shared = strong[:, number] & strong[:, other] & away[:, number] & away[:, other]
            smaller = min(strong[:, number].sum(), strong[:, other].sum())
            if shared.sum() >= max(BLEED * smaller, BLEED_VERTICES):
                flags.append("BLEEDS with %s: %d vertices, z %s..%s" % (
                    found[other][0].name, shared.sum(), num(positions[shared, 2].min()), num(positions[shared, 2].max())))
        flagged += bool(flags)
        out("  %-26s %5d  %-10s %5d  %-20s %-11s %s" % (
            label, len(chain), span, mine.sum(), fmt(points.mean(axis=0)),
            "%.2f..%.2f" % (points[:, 2].min(), points[:, 2].max()), "; ".join(flags)))
    if flagged:
        NEXT.append("fix the flagged chains bone by bone, then rename the bones to our scheme")
    else:
        NEXT.append("rename the bones to our scheme")
    out("RIG      %s" % ("%d chain%s flagged (REACHES: a part without a full chain; BLEEDS: two chains move one "
                         "part)" % (flagged, "" if flagged == 1 else "s")
                         if flagged else "every chain covers what it moves"))


def inspect(path):
    gltf, binary, size = read_glb(path)
    report_file(path, gltf, binary, size)
    report_materials(gltf, binary)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    mesh = scene_mesh()
    positions, low, high = report_mesh(gltf, mesh)
    report_eyes(mesh, positions, low, high)
    report_body(mesh, positions, low, high)
    report_rig(mesh, positions, low, high)
    out("NEXT     " + "; ".join(NEXT))


def main():
    if bpy is not None:
        inspect(sys.argv[sys.argv.index("--") + 1])
        return 0
    if len(sys.argv) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    command = [sys.executable, os.path.join(HERE, "blender.py"), "--background", "--factory-startup",
               "--python", os.path.abspath(__file__), "--", os.path.abspath(sys.argv[1])]
    try:
        run = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                             timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        print("inspect_meshy.py: Blender didn't finish within %d s" % TIMEOUT, file=sys.stderr)
        return 1
    lines = [line[len(PREFIX):] for line in run.stdout.splitlines() if line.startswith(PREFIX)]
    print("\n".join(lines))
    if run.returncode != 0:
        print(run.stdout + run.stderr, file=sys.stderr)
    return run.returncode


if __name__ == "__main__":
    sys.exit(main())
