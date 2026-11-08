# 3D minion models

One GLB per card id (Trellis2/Pixal3D on Ian's PC via ComfyUI).
src/ holds the full-body reference image each model was built from and the per-card descriptions used to make them.

- grunk_dynamite: Ian's Grok wind-up reference (approved 2026-11-01)

## Shipping
- Models are optimized for the game with `tools/optimize_glb.py` (512px JPEG
  textures, no tangents, 16-bit indices); the full-resolution originals are
  in git history (commit 784a264 and earlier) and on the ComfyUI PC.
- This folder has a `.gdignore`: the editor does not import the GLBs. They
  ship raw in `everdeck_models_NN.pck` packs, each under 20MB
  (`tools/build_models_pack.gd`), and
  `ModelLib` parses them at runtime.
