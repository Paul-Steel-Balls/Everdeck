# Everdeck Lab

The game's rules and computer opponent, text only, with no engine: a
small Rust program for balance testing. It plays the same games as the
Godot game, move for move (see "Parity" below), at roughly 1,500-2,500
games per second on two cores (Godot's headless sims: about 13).

Build (from this folder): `cargo build --release`. The program is
`target/release/everdeck_lab`. No outside packages.

## Commands

    everdeck_lab meta   --games 300 [--seed 1] [--decks f.json] [--out games.jsonl]
    everdeck_lab search --class barnacle --iters 150 --games 300 [--field f.json] [--start f.json] [--out d.json]
    everdeck_lab pick   --pool f.json --games 1000 [--out dir]
    everdeck_lab play   new --me barnacle --vs grunk [--seed 5] [--second] --save g.json
    everdeck_lab play   move N | end | show --save g.json
    everdeck_lab cards  [--class barnacle] [--find draw]

Every command takes `--patch f.json`: what-if card and Signature Move
changes, in memory only, the same format as the Godot sims' SIM_PATCH:

    {"cards": {"barnacle_mate": {"attack": 2, "health": 2, "keywords": ["windfury"], "text": "Encore."}},
     "powers": {"larry": {"value": 2}},
     "deckhand": {"health": 2},
     "payoff_cap": 3}

`meta` and `pick` print each Boss's win rate, going first, the matchup
grid and the worst matchup. `meta --out` writes the same records as
tools/sim_meta.gd, so tools/meta_report.py reads them too.

`play` is for playtesting by text: the board, your hand and a numbered
list of legal moves. `move 3` plays move 3, `end` ends your turn and the
bot takes its turn. The game is saved as its seed plus your moves.

## Where the cards come from

`data/rules.json`, exported by the game:

    godot --headless --path . -s res://tools/lab_export.gd

Re-export after any card or Signature Move change.

## Parity

The Lab is a second copy of the rules (scripts/game_state.gd) and the bot
(scripts/ai_player.gd), so it must never drift. `bash lab/parity.sh`
plays the same seeded games in both, with the bot's look-ahead dice
pinned, and compares every game: winner, turns, Health, every card played
and when. It must say "0 different". It runs plain games and games with
`data/stress_patch.json` (random new keywords and triggers on about 90
cards), so every rules path is exercised.

When the game's rules change: make the same change in `src/game.rs` (or
`src/ai.rs` for the bot), then run the parity check.

First check, Nov 10 2026: 1,152 games compared (plain, stress patch,
Barnacle drafts with a going-first variant): 0 different.
