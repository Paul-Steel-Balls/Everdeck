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

## Agatha drafts 4-7 (Nov 11, Lab, 3-seed average)

| Draft | Change on top of draft 3 | Agatha | Outside 60/40 | Presto vs Agatha | Agatha vs Reginald |
|---|---|---|---|---|---|
| 3 | (heal payoffs, defensive nerfs) | 53.8% | many | 24/76 | 29/71 |
| 4 | Nova costs 5; Ladle Storm hits one Crew for 2; Unleashed Final Bow heals 5; Written Out of the Will costs 3; Dish, Knitting +1 Health; Cookies +1 Attack | 53.0% | 2 | 26/74 | 28/72 |
| 5 | 4 + Ironclad Doily loses Bouncer, Soup Kitchen Bouncer 3/4, Soup Pot 5/7 | 51.5% | 3 | 19/81 | 25/75 |
| 6 | 4 + Nova and Wrath (Mild) deal 1; two Stunt Double Bouncers | 62.8% | 4 | 23/77 | 61/39 (Reginald 39%) |
| 7 | 4 + one Stunt Double Bouncer | 56.3% | 3 | 29/71 | 34/66 |

Knockout tests (fixed best decks, 600 games):
- Agatha without board wipes: beats Presto 46% (was 73%) but Reginald only 9% (was 29%).
- Reginald without his 6 targeted-removal cards: Agatha beats him 76%.
- Presto without burn: 2%. Without card draw: 5%. Presto has no way past Bouncers except burn.
Conclusion: the two worst matchups are fixed from the other side (Presto needs a way past Bouncers; Reginald's removal suite is too deep), not by gutting Agatha. Draft 4 saved as lab/patches/agatha_draft4.json.

## Deeper baseline (Nov 11): the old decks were under-searched

Presto draft 1 hit ~63%, but its deck won 58% even with Presto's original
cards: the search had found a better Presto list. So the baseline itself
was weak. Fix: converge.sh, every Boss searched 3 seeds x 400 iterations
per round against the newest field, 3 rounds (cards: v0.9.4 + Agatha
draft 4). Also fixed: Boss evals now carry the other Bosses' tuned decks
forward (POOL=), so Agatha isn't tested with decks built for old cards.

| Boss | quick baseline | round 1 | round 2 | round 3 |
|---|---|---|---|---|
| Larry | 48.2 | 52.2 | 54.6 | 55.5 |
| Presto | 47.3 | 51.7 | 53.8 | 54.1 |
| Reginald | 50.2 | 54.7 | 52.9 | 53.1 |
| Agatha | 53.0 | 49.1 | 49.6 | 48.3 |
| Barnacle | 47.7 | 45.5 | 45.3 | 44.6 |
| Grunk | 53.6 | 46.8 | 43.8 | 44.3 |

Round 3: 6 matchups outside 60/40; worst Agatha vs Reginald 33/67,
Barnacle vs Presto 33/67, Presto vs Agatha 35/65. Rounds 2-3 move about
1 point, so it's close to settled. New baseline = cv1/r3.

## Planner baseline (Nov 11): same cards, the smarter bot plays both sides

Same as the deep baseline, but every game is played by the planner bot
(Hard mode, beam 4). Round 3 hit the 2-hour limit; rounds 1-2 shown.

| Boss | greedy bot (cv1 r3) | planner r1 | planner r2 |
|---|---|---|---|
| Presto | 54.1 | 59.2 | 61.0 |
| Larry | 55.5 | 54.4 | 56.1 |
| Grunk | 44.3 | 48.1 | 49.7 |
| Barnacle | 44.6 | 47.4 | 46.2 |
| Reginald | 53.1 | 49.4 | 46.1 |
| Agatha | 48.3 | 41.5 | 40.9 |

Going first 43.6%. Worst: Reginald vs Presto 21/79, Barnacle vs Presto
29/71, Agatha vs Reginald 34/66, Agatha vs Larry 35/65. Takeaway: card
draw plus cheap Tricks (Presto) reward planning; Agatha's Bouncer-and-heal
plan was flattering the weak bot. All balance passes from here on use the
planner. New baseline = cv2/r2.

## Planner passes g1-g6 (Nov 11, Lab only; 2 converge rounds each)

Method: per-card knockouts (each card swapped for a plain same-cost
Crew, Boss win% change), then whole-package converge rounds where every
Boss re-searches its list against the newest field.

Knockout findings (planner):
- Oops, Wrong Hand! was worth +13.6 to Larry as ONE copy (the planner
  reads both hands). Cost 2 -> 5 in all drafts.
- Presto's power comes from removal on a body (Blast Scholar, Orb of
  Oops, Zapper, Part-Time Dragon) and cheap draw-2 (Bookworm, Wisdom).
  His cheap "draw a card" Crew play WORSE than plain 2/2s.
- Agatha's heal payoffs only fired when she was damaged. Fix approved by
  Ian (Nov 11): a heal at full Health still counts ("every heal pays
  off"). Her payoff Crew (Carol, Volunteer) then knock out at +4-6.
- Going first was ~44% with 5 cards + 1 Penny. Approved (Nov 11): going
  second gets 4 cards + 2 Lucky Pennies.

| Draft | Main changes | Presto | Larry | Reginald | Grunk | Barnacle | Agatha | first |
|---|---|---|---|---|---|---|---|---|
| base (cv2 r2) | v0.9.4 + Agatha draft 4 | 61.0 | 56.1 | 46.1 | 49.7 | 46.2 | 40.9 | 43.6 |
| g2 | Oops 5 mana; Mirror Mage, Circle, Sage -1 Attack; Agatha power heals 3; Carol 3/5; Volunteer +1/+1; Reginald knights package | 54.2 | 54.2 | 50.5 | 48.6 | 45.6 | 46.9 | 46.4 |
| g4 | g2 + overheal + Knitting 2/4 | 64.1 | 45.2 | 50.0 | 50.6 | 40.6 | 49.4 | 47.1 |
| g5 | g4 + Blast Scholar 3/2, Orb 4 mana, Deckhand 1/3 | 58.6 | 42.7 | 54.2 | 41.4 | 54.6 | 48.6 | 46.0 |
| g6 | g5 + Bookworm 4 mana, Wisdom 3 mana, Final Exam 6 mana | 46.3 | 43.2 | 50.9 | 47.1 | 61.5 | 51.0 | 44.9 |

g4 -> g5 Presto jumped because the search found a new list; single
rounds swing several points, so each draft gets at least 2 rounds.

## Planner passes g7-g10 (Nov 11, new default rules: overheal, 4 cards + 2 Pennies)

| Draft | Main changes | Presto | Larry | Reginald | Grunk | Barnacle | Agatha | first | outside 60/40 |
|---|---|---|---|---|---|---|---|---|---|
| g7 | g6, Deckhand back to 1/2; Larry random-effect payoffs + On Credit; Grunk lit fuses | 50.6 | 45.3 | 58.1 | 49.7 | 44.7 | 51.6 | 46.1 | 4 |
| g8 | g7; High Marshal 2/3, Judgment 3/3, Twin-Blade 3/3; Bettor 3-mana 3/3, Dice Boy 2/3, Lucky Seven 5/5; Flag Bearer, Bosun 2/3 | 47.8 | 54.1 | 50.4 | 53.4 | 44.1 | 50.2 | 46.4 | 3 |
| g9 | g8 + Scout Parrot 3/4 | 51.1 | 49.1 | 46.1 | 50.5 | 55.0 | 48.2 | 45.8 | 4 |
| g10 | g8 + Judgment 3/4 (from g9's pool) | 48.5 | 51.3 | 51.7 | 50.5 | 47.0 | 51.1 | 44.4 | 3 |
| g10 confirm | 3 picks x 1000 games on the final pool | 48.1 | 53.8 | 49.1 | 48.0 | 47.1 | 54.1 | 45.4 | 4 |

No kills from 30 Health in one turn in 7,200 planner games (g8 decks);
the biggest one-turn drop was 23.

Going first under the g10 decks (fixed lists, 400 games per pairing):
4 cards + 2 Pennies 45.0%; 4 + 1 Penny 59.7%; 4 + 1 Penny and going
second starts at 36 Health 52.7%, at 39 Health 48.8%; 5 + 1 Penny ~44%.
One card or one Penny is worth ~15 points to the planner; 1 Health ~1.

## Passes g11-g16 (Nov 11-12) and a steadier yardstick

Single "best list per Boss" picks swing up to 10 points from run to run
(one sharp counter-list can make a matchup read 12/88). From g12 on, each
draft is also scored by **field**: each Boss's top 3 lists against every
other Boss's top 3 (9 rotations x 200 games per pairing). Field numbers
move 2-4 points between rounds instead of 5-10.

| Draft | Change | field r1 | field r2 |
|---|---|---|---|
| g12 | g11 (Carol back to shipped, Dice Boy 2/2) + Agatha's power back to heal 2 | Barn 56.5, Pres 51.1, Lar 49.1, Gru 49.0, Reg 49.0, Aga 45.2 | Barn 53.8, Pres 51.6, Lar 50.3, Reg 49.5, Aga 48.1, Gru 46.6 |
| g13 | g12; Flag Bearer, Bosun back to 2/2; Boombox 3/3, War Machine 3/5 | Pres 56.8, Gru 51.0, Reg 50.9, Lar 50.5, Barn 47.5, Aga 43.4 | Pres 57.4, Lar 51.0, Reg 49.0, Aga 49.0, Gru 48.6, Barn 45.1 |
| g14 | g13 + Flag Bearer 2/3 | Pres 55.2, Reg 52.7, Lar 50.1, Gru 47.6, Aga 47.5, Barn 46.8 | Pres 55.9, Lar 51.4, Aga 50.0, Reg 49.0, Barn 47.1, Gru 46.6 |
| g15 | g14 + Tower Librarian 2/3, Thesis Defense 8 mana | Reg 54.7, Aga 50.8, Lar 50.2, Barn 49.6, Gru 48.7, Pres 45.9 | Lar 54.7, Aga 51.4, Reg 50.1, Barn 48.3, Pres 47.9, Gru 47.5 |
| g16 | g15 + Three-Card Monte 3/3, Blackjack 2/2 | Reg 54.7, Aga 51.7, Gru 51.2, Barn 49.7, Lar 47.5, Pres 45.2 | Reg 54.2, Aga 52.1, Barn 49.6, Gru 49.2, Pres 48.2, Lar 46.6 |

Two matchups stay lopsided in every draft: Presto vs Agatha (~26/74:
her healing outlasts his burn) and Agatha vs Reginald (~32/68: buffed,
Stunt Double knights shrug off her board wipes).
