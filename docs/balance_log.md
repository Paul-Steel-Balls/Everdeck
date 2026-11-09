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
