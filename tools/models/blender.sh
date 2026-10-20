#!/usr/bin/env bash
# Starts Blender for the model tools, on the GPU where it can (#1050). Under WSL, Mesa's default
# OpenGL falls back to the CPU's software rasteriser; its d3d12 driver reaches the real GPU, but
# only when asked for. Only this process gets it, never the shell: Godot's Compatibility renderer
# skins meshes on the GPU, and on d3d12 that breaks every skinned mesh. Blender skins on the CPU,
# so its renders come out the same, only faster.
#   tools/models/blender.sh --background --factory-startup --python <script.py> -- <args>
set -euo pipefail
if [[ -e /dev/dxg && -z "${GALLIUM_DRIVER:-}" ]]; then
	export GALLIUM_DRIVER=d3d12
fi
exec blender "$@"
