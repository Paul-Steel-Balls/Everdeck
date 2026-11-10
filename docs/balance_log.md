# Everdeck balance log

Every balance change, why it was made, and the numbers behind it. Cards
and balance change only with Ian's OK.

Targets (agreed 2026-11-09):
- Every Boss 47-53% with tuned decks
- Matchups: 55/45 is the goal, 60/40 at most (Ian, Nov 10; was "no worse
  than 35/65"). Counters are fine when they are designed (healer beats
  self-damage mage) and stay within that; two real decks per Boss make a
  counter a deck choice, not a class sentence.
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

### Steadier method: best list from a shared pool (`tools/sim_pick.gd`)

One search per Boss was too noisy (unchanged Agatha ranged 46-63%).
Now every list found in every run (about 10 per Boss) is scored against
the other Bosses' lists under the patch; the top 3 per Boss become the
field; each Boss then plays his best list. About 20 minutes per patch.

| Boss | No change | E | D | F | G |
|---|---|---|---|---|---|
| Grunk | 60.5% | 54.1% | 54.4% | 55.8% | 57.9% |
| Agatha | 59.5% | 57.9% | 60.2% | 54.2% | 46.1% |
| Presto | 54.3% | 50.9% | 48.1% | 48.2% | 49.9% |
| Reginald | 47.6% | 53.2% | 46.6% | 46.8% | 51.3% |
| Larry | 36.8% | 36.6% | 46.3% | 48.2% | 48.2% |
| Barnacle | 41.3% | 47.3% | 44.5% | 46.8% | 46.6% |
| Going first | 47.1% | 45.9% | 46.8% | 47.5% | 47.8% |
| Worst matchup | 24/76 | 18/82 | 16/84 | 29/71 | 30/70 |

- E: Larry's Signature Move 2 damage; Deckhand 1/2.
- D: E + Dice Boy and Chip 2/2, Lucky Seven and Whale +1 Health.
- F: D + Agatha's tea heals 2 (was 3).
- G: D + Meatloaf Monday, Ladle of Justice, Disappointed Sigh, Soup Pot -1 Health.

Agatha is genuinely strong (her top four lists all score 56-61% with no
change), and her healing beats Presto 76-84%, which cancels his
pay-health-to-draw plan. F is the best so far: spread 47-56%, down from
37-61%. Testing H = F + Bomb Chucker 4/3 and Grunk Jr. 4 split damage.

| Boss | H (F + Bomb Chucker 4/3, Grunk Jr. 4 split) |
|---|---|
| Agatha | 58.8% |
| Presto | 51.5% |
| Reginald | 50.1% |
| Barnacle | 50.1% |
| Larry | 46.3% |
| Grunk | 43.1% |

H overcorrects Grunk and Agatha bounces back. Not shipped.

## Patch 3, v0.9.3 (2026-11-09): F shipped (Ian approved)

Larry: Feeling Lucky 2 damage; Dice Boy 2/2, Chip 2/2, Lucky Seven 5/5,
The Whale 5/5. Barnacle: Deckhand 1/2. Agatha: tea restores 2.
Result (steady method): every Boss 46.8-55.8%, going first 47.5%.
Still open: Grunk 55.8%, Agatha vs Presto 71/29, Echo Blast on watch.
Note: Harpoon Gunner's Entrance Deckhand is still a 1/1 (its own token);
only the Signature Move Deckhand changed.

## Barnacle rework (mechanics pass), proposed Nov 10, awaiting Ian's OK

lab/patches/barnacle_rework.json: 15 Barnacle cards reworked. Tested in
the Lab (4 deck searches, pick at 1,000 games per list, then 54,000 fresh
games): Barnacle 48.6% (today 46.7%), spread 47.2-54.8%, burst unchanged
(18 at 10 mana). First drafts were 58-60%; leave-one-out found Crow's
Nest Lookout (~9 pts) and Ship's Cook (~7 pts) carried it.
Approved by Ian Nov 10 and applied: v0.9.4.

## Bot fix: no more peeking (Nov 10)

The bot's look-ahead copies kept the real deck order, so testing a draw
card showed it the exact card it would draw, and the opponent's hand was
visible too. Now each look-ahead copy shuffles the bot's own deck and
deals the opponent's hand afresh from their unknown cards (game and Lab;
parity 576/576). Steady test after the fix (v0.9.4 cards, 1,000 games per
list): Grunk 53.4, Agatha 51.2, Reginald 50.4, Barnacle 50.3, Larry 47.6,
Presto 47.1; going first 45.9%. Worst: Agatha vs Reginald 27/73, Presto
vs Agatha 31/69.
