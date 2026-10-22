"""The shared Blender library every model script in packages/game-models/ builds on (model skill, #995).

A model script holds only its model's parameters and its own parts; everything reusable lives
here: the scene and the glTF export (scene), materials (materials), soft metaball bodies (body),
rigid parts such as crystals and fur tufts (parts), patterns laid on a body's surface, runes and
veins (surface), detailed eyes (eyes), the quadruped armature (quadruped), skin weights (weights),
clips (clips), the motion between their keys (motion) and a built model read back for the checks
(imported). Import it from a model script with `sys.path.insert(0, <packages/game-models>)`.
"""
