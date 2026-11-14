"""The shared Blender library every model script builds on, each in its
model's build folder, resourcepacks/default/models/<folder>/build/ (#2438; model skill, #995).

A model script holds only its model's parameters and its own parts; everything reusable lives
here: the scene and the glTF export (scene), materials (materials), soft metaball bodies (body),
rigid parts such as crystals and fur tufts (parts), patterns laid on a body's surface, runes and
veins (surface), detailed eyes (eyes), the quadruped armature (quadruped), skin weights (weights),
clips (clips), the motion between their keys (motion), wisps floating beside a body (wisps), a
generated model's own rig adopted (rigged) and its many-bone legs and stalks for the clips
(adopted), a built model read back for the checks (imported), the checks' summary mode (summary),
a model script's gait values from its arguments (tuning) and mesh steps that come out alike on
any count of Blender's threads (fixed_order). Import it from a model script with
`sys.path.insert(0, <src/game-models>)`.
"""
