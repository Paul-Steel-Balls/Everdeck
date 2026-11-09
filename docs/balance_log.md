# Everdeck balance log

Every balance change, why it was made, and the numbers behind it. Cards
and balance change only with Ian's OK.

Targets (agreed 2026-11-09):
- Every Boss 47-53% with tuned decks
- No matchup worse than 35/65
- Going first wins 48-52%
- No kill from full Health (30) in one turn
- At least two viable lists per Boss

Tools: `tools/sim_meta.gd` (AI vs AI), `tools/sim_search.gd` (deck
search), `tools/sim_burst.gd` (most damage in one turn), and
`tools/meta_report.py` / `tools/meta_datasets.py` (reports).

## Patch 1 (earlier): Player 2 gets 5 cards + Lucky Penny

## Patch 2, v0.9.2 (2026-11-09): payoffs count at most 3 other cards

Cards: Firecracker Mage, Final Exam, Thesis Defense, Graduation Day.
Text now ends "...for each other card you played this turn (up to 3)."
Rule: `GameState.payoff_cap = 3`.

Why: the burst checker found Presto could deal 40 damage in one turn at
10 mana and kill from full Health at 6 mana (two Firecracker Mages plus
cheap cards). The bots never set this up; players would.

Tested (most damage from hand, empty boards):

| Rule | At 10 mana | Earliest full-Health kill |
|---|---|---|
| No cap (before) | 40 | 6 mana |
| Mana Potion / Mana Wisp don't count | 35 | 8 mana |
| Cap 4 | 34 | 9 mana |
| **Cap 3 (chosen)** | **28** | **none** |
| Cap 2 | 24 | none |

For comparison: Grunk 26, Larry 24, Barnacle 18, Reginald 16, Agatha 14.
Presto keeps the biggest burst in the game but can't kill from full Health.

Watch: Echo Blast (1 mana, 4 damage to a random enemy) is in every Presto
burst line and scores high in the card data.

## Also fixed (AI, not balance): the computer never played the Lucky Penny

Before the fix, going first won 60% of bot games; after, 46%. Every
earlier bot number was skewed by this.

## Patch 3 candidates (testing, nothing applied)

Method: every Boss's list is re-searched under the patch (100 steps,
160 games each, against every earlier round's lists), then a 300-game
meta per pairing. Every patch is compared with a no-change control run
the same way, so a Boss that only looked weak because the search missed
his best list isn't "fixed".

| Boss | Control (v0.9.2) | A2 |
|---|---|---|
| Presto | 64.9% | 57.5% |
| Grunk | 60.3% | 51.7% |
| Reginald | 55.7% | 48.9% |
| Agatha | 48.1% | 46.5% |
| Barnacle | 37.7% | 38.6% |
| Larry | 33.3% | 56.8% |
| Going first | 48.5% | 47.3% |

A2: Larry +stats on 11 cards and Signature Move 2 damage; Agatha -1
Health on 4 cards. Larry overshoots, Barnacle unchanged.

Next: B (three Signature Moves only: Larry 2 damage, Presto takes 3,
Barnacle's Deckhand 2/1) and C (Larry 2 damage, Deckhand 2/2).
Sim-only hook added: a patch can set `"deckhand": {...}`.

| Boss | B | C |
|---|---|---|
| Barnacle | 58.1% | 64.5% |
| Grunk | 57.1% | 63.7% |
| Agatha | 52.8% | 46.3% |
| Reginald | 48.5% | 49.6% |
| Larry | 43.0% | 42.7% |
| Presto | 40.5% | 33.2% |
| Going first | 51.0% | 53.1% |

Findings:
- Barnacle's Deckhand is a big lever: 2/1 is +20 points, 2/2 is +27.
  Both overshoot.
- Presto falls without being touched (C): his 65% was mostly from
  farming weak Barnacle and Larry (79% vs each). Fix the bottom first.
- Larry's Signature Move at 2 alone: 33% -> 43%. Not enough by itself.
- Run-to-run noise: Agatha, unchanged in every run, ranged 46-53%. The
  47-53% target is about as tight as one run can measure.

Next: E (Larry 2 damage, Deckhand 1/2) and D (E plus 1-drops 2/2 and
Lucky Seven / Whale +1 Health).
