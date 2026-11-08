# Everdeck

A PvP card game for Windows PC, built in Godot 4.7. Six rival Bosses, each with its own deck, themed arena and set piece. Cards summon 3D hologram Crew onto a floating battlefield; Tricks are spells.

## Play

The playable build is the **Play** folder: `Everdeck.exe`, `Everdeck.pck` and the `everdeck_*.pck` data packs (art, music, 3D models) side by side. Download it from the latest release on this repo's Releases page, unzip, and run `Everdeck.exe`.

## Online play (in progress)

Two PCs on the same Tailscale network: one player hosts, the other joins with the host's Tailscale name or address.

## For developers

- Open the folder in Godot 4.7.2.
- Tests: `godot --headless --path . res://tests/test_main.tscn`
- `models3d/` holds the raw 3D models (glTF binary). They are excluded from the code export and shipped as `everdeck_models_NN.pck` packs built by `tools/build_models_pack.gd`. Art and music packs are built the same way (`tools/build_art_packs.gd`, `tools/build_music_pack.gd`).
- `tools/shots/` holds the screenshot and movie harnesses used for review.
