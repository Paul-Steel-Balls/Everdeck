//! The computer opponent, ported from scripts/ai_player.gd: try every
//! legal action on a copy, score the result, take the best. Same numbers,
//! same order of operations, so it picks the same moves as the game's bot.

use crate::data::*;
use crate::game::*;
use crate::rng::Rng;

pub const WIN_SCORE: f64 = 100000.0;
pub const TEMPO_PER_MANA: f64 = 0.35;
pub const MIN_GAIN: f64 = 0.05;
pub const SAMPLES_RANDOM: i32 = 4;
const RANDOM_EFFECTS: [&str; 7] = ["random", "roulette", "coin", "swap", "steal", "recruit", "flip"];

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Act {
    Play(usize, T),
    Power(T),
    Attack(usize, T),
    End,
}

/// Lab-only turn planner: 0 = the game's one-move-at-a-time bot (parity),
/// N = beam search over move sequences, N lines kept per step.
pub static PLAN: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(0);
pub const PLAN_DEPTH: usize = 6;
/// -1: everyone plans; 0 or 1: only that seat (0 = went first) plans.
pub static PLAN_SEAT: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(-1);

pub struct Ai {
    pub rng: Rng,
    pub sloppiness: f64,
}

impl Ai {
    pub fn new(seed: i64) -> Ai {
        Ai { rng: Rng::new(seed), sloppiness: 0.0 }
    }

    pub fn next_action(&mut self, gs: &Game, me: usize) -> Act {
        if gs.winner != -1 || gs.active != me {
            return Act::End;
        }
        let beam = PLAN.load(std::sync::atomic::Ordering::Relaxed);
        let seat = PLAN_SEAT.load(std::sync::atomic::Ordering::Relaxed);
        if beam > 0 && (seat < 0 || seat == me as i64) {
            return plan(gs, me, beam as usize);
        }
        let base = evaluate(gs, me);
        let mut scored: Vec<(f64, Act)> = vec![];
        for a in legal_actions(gs, me) {
            let samples = if is_random(gs, me, a) { SAMPLES_RANDOM } else { 1 };
            let mut total = 0.0;
            let mut ok = true;
            for _ in 0..samples {
                let mut g = look(gs, me);
                if !apply(&mut g, me, a) {
                    ok = false;
                    break;
                }
                total += evaluate(&g, me);
            }
            if !ok {
                continue;
            }
            let mut diff = total / samples as f64 - base;
            if gives_mana(gs, me, a) || pops_shield(gs, a) {
                let mut g2 = look(gs, me);
                if apply(&mut g2, me, a) {
                    diff += best_followup(&g2, me);
                }
            }
            let tempo = if matches!(a, Act::Power(_)) && diff.abs() < 0.001 { 0.0 } else { tempo(gs, me, a) };
            scored.push((diff + tempo, a));
        }
        if scored.is_empty() {
            return Act::End;
        }
        let mut bi = 0;
        for i in 1..scored.len() {
            if scored[i].0 > scored[bi].0 {
                bi = i;
            }
        }
        let best = scored[bi].0;
        if best >= WIN_SCORE * 0.5 {
            return scored[bi].1;
        }
        if best < MIN_GAIN {
            return Act::End;
        }
        let mut pick = scored[bi];
        if self.sloppiness > 0.0 && scored.len() > 1 && self.rng.randf() < self.sloppiness {
            let mut a2: i64 = -1;
            for i in 0..scored.len() {
                if i != bi && (a2 == -1 || scored[i].0 > scored[a2 as usize].0) {
                    a2 = i as i64;
                }
            }
            let alt = scored[a2 as usize];
            if alt.0 >= MIN_GAIN && alt.0 >= best * 0.6 {
                pick = alt;
            }
        }
        pick.1
    }
}

/// Try sequences of moves this turn (beam search), score where each line
/// ends up, and take the first move of the best line. Re-plans every move,
/// so dice and draws are seen as they land.
fn plan(gs: &Game, me: usize, width: usize) -> Act {
    let root = look(gs, me);
    let base = evaluate(&root, me);
    let mut best = (base, Act::End);
    let mut beam: Vec<(f64, Game, Act, f64)> = vec![(base, root, Act::End, 0.0)];
    for _ in 0..PLAN_DEPTH {
        let mut cand: Vec<(f64, Game, Act, f64)> = vec![];
        for (_, g, first, tsum) in &beam {
            for a in legal_actions(g, me) {
                let mut g2 = g.clone_for_ai();
                if !apply(&mut g2, me, a) {
                    continue;
                }
                let t = tsum + tempo(g, me, a);
                let f = if *first == Act::End { a } else { *first };
                let s = evaluate(&g2, me) + t;
                if g2.winner == me as i32 {
                    return f;
                }
                cand.push((s, g2, f, t));
            }
        }
        if cand.is_empty() {
            break;
        }
        cand.sort_by(|x, y| y.0.partial_cmp(&x.0).unwrap_or(std::cmp::Ordering::Equal));
        cand.truncate(width);
        if cand[0].0 > best.0 {
            best = (cand[0].0, cand[0].2);
        }
        beam = cand;
    }
    if best.0 - base < MIN_GAIN {
        return Act::End;
    }
    best.1
}

/// A look-ahead copy with the hidden cards hidden (AIPlayer._look): own
/// deck order unknown, the opponent's hand and deck unknown.
fn look(gs: &Game, me: usize) -> Game {
    let mut g = gs.clone_for_ai();
    let mut deck = std::mem::take(&mut g.players[me].deck);
    shuffle(&mut g, &mut deck);
    g.players[me].deck = deck;
    let foe = 1 - me;
    let n = g.players[foe].hand.len();
    let mut pool = std::mem::take(&mut g.players[foe].hand);
    pool.append(&mut g.players[foe].deck);
    shuffle(&mut g, &mut pool);
    g.players[foe].deck = pool.split_off(n);
    g.players[foe].hand = pool;
    g
}

fn shuffle(g: &mut Game, a: &mut [CardId]) {
    for i in (1..a.len()).rev() {
        let j = g.rng.randi_range(0, i as i64) as usize;
        a.swap(i, j);
    }
}

fn gives_mana(gs: &Game, me: usize, a: Act) -> bool {
    match a {
        Act::Play(hi, _) => db().card(gs.players[me].hand[hi]).effect == Eff::GainMana,
        _ => false,
    }
}

fn pops_shield(gs: &Game, a: Act) -> bool {
    match a {
        Act::Attack(_, T::Minion(o, i)) => i >= 0 && (i as usize) < gs.players[o].board.len() && gs.players[o].board[i as usize].has(KW_SHIELD),
        _ => false,
    }
}

fn best_followup(gs: &Game, me: usize) -> f64 {
    let base = evaluate(gs, me);
    let mut best = 0.0;
    for b in legal_actions(gs, me) {
        if gives_mana(gs, me, b) {
            continue;
        }
        let mut g = look(gs, me);
        if !apply(&mut g, me, b) {
            continue;
        }
        let gain = evaluate(&g, me) - base + tempo(gs, me, b);
        if gain > best {
            best = gain;
        }
    }
    best
}

pub fn legal_actions(gs: &Game, me: usize) -> Vec<Act> {
    let mut out = vec![];
    let p = &gs.players[me];
    let d = db();
    for i in 0..p.hand.len() {
        if !gs.can_play(me, i) {
            continue;
        }
        let card = d.card(p.hand[i]);
        let opts = gs.card_target_options(me, card);
        if opts.is_empty() {
            out.push(Act::Play(i, T::None));
        } else {
            for t in opts {
                out.push(Act::Play(i, t));
            }
            if card.kind == Kind::Minion {
                out.push(Act::Play(i, T::None));
            }
        }
    }
    let hp_opts = gs.hero_power_target_options(me);
    if hp_opts.is_empty() {
        if gs.can_use_hero_power(me, T::None) {
            out.push(Act::Power(T::None));
        }
    } else {
        for t in hp_opts {
            if gs.can_use_hero_power(me, t) {
                out.push(Act::Power(t));
            }
        }
    }
    for b in 0..p.board.len() {
        if !gs.can_attack(me, b) {
            continue;
        }
        for t in gs.valid_attack_targets(me) {
            out.push(Act::Attack(b, t));
        }
    }
    out
}

pub fn apply(gs: &mut Game, me: usize, a: Act) -> bool {
    match a {
        Act::Play(hi, t) => gs.play_card(me, hi, t),
        Act::Power(t) => gs.use_hero_power(me, t),
        Act::Attack(b, t) => gs.attack(me, b, t),
        Act::End => false,
    }
}

fn is_random(gs: &Game, me: usize, a: Act) -> bool {
    match a {
        Act::Power(_) => gs.hero_power(me).map(|h| h.effect_name.contains("random")).unwrap_or(false),
        Act::Play(hi, _) => {
            let c = db().card(gs.players[me].hand[hi]);
            let blob = format!("{} {} {}", c.effect_name, c.effect2_name, c.deathrattle_name).to_lowercase();
            RANDOM_EFFECTS.iter().any(|k| blob.contains(k))
        }
        _ => false,
    }
}

fn tempo(gs: &Game, me: usize, a: Act) -> f64 {
    match a {
        Act::Play(hi, _) => TEMPO_PER_MANA * db().card(gs.players[me].hand[hi]).cost as f64,
        Act::Power(_) => TEMPO_PER_MANA * HERO_POWER_COST as f64,
        _ => 0.0,
    }
}

pub fn evaluate(gs: &Game, me: usize) -> f64 {
    if gs.winner == me as i32 {
        return WIN_SCORE;
    }
    if gs.winner == 1 - me as i32 {
        return -WIN_SCORE;
    }
    let mine = &gs.players[me];
    let theirs = &gs.players[1 - me];
    let mut v = side_value(mine) - side_value(theirs);
    let mut threat = 0.0;
    for m in &theirs.board {
        if m.frozen > 0 {
            continue;
        }
        threat += m.attack as f64 * if m.has(KW_WINDFURY) { 2.0 } else { 1.0 };
    }
    let my_hp = mine.hp;
    v -= threat * if my_hp > 15 { 0.5 } else if my_hp > 8 { 0.9 } else { 1.6 };
    if threat >= my_hp as f64 {
        v -= 25.0;
    }
    v
}

pub fn health_value(hp: i32) -> f64 {
    let h = hp.max(0) as f64;
    1.8 * h.min(8.0) + 1.0 * (h - 8.0).clamp(0.0, 7.0) + 0.6 * (h - 15.0).max(0.0)
}

fn keyword_value(m: &Minion, atk: f64) -> f64 {
    let mut v = 0.0;
    if m.has(KW_SHIELD) {
        v += 2.0 + atk * 0.6 + m.health.max(0) as f64 * 0.2;
    }
    if m.has(KW_STEALTH) {
        v += 0.8;
    }
    if m.has(KW_WINDFURY) {
        v += atk * 0.9;
    }
    if m.has(KW_POISON) {
        v += 2.5;
    }
    if m.has(KW_LIFESTEAL) {
        v += atk * 0.5;
    }
    if m.frozen > 0 {
        v -= atk * 0.6;
    }
    if m.silenced {
        return v;
    }
    let c = db().card(m.card);
    for t in &c.triggers {
        let amt = t.value as f64;
        if t.when == When::EndOfTurn || t.when == When::StartOfTurn {
            v += 1.5 + amt * 1.2;
        } else {
            v += 1.0 + amt * 0.6;
        }
    }
    if c.vibe.is_some() {
        v += 0.6;
    }
    v
}

fn side_value(p: &Player) -> f64 {
    let mut v = 0.0;
    v += health_value(p.hp);
    for m in &p.board {
        let atk = m.attack as f64;
        let health = m.health.max(0) as f64;
        v += atk * 1.3 + health * 1.0 + 0.8;
        if m.taunt {
            v += 0.8 + health * 0.2;
        }
        v += keyword_value(m, atk);
    }
    v += (p.hand.len() as f64).min(8.0) * 0.9;
    v -= p.overload_next as f64 * 0.6;
    v
}

/// A playable deck with a mana curve (AIPlayer.build_deck).
pub fn build_deck(class: &str, seed: i64) -> Vec<CardId> {
    let d = db();
    let mut r = Rng::new(0);
    if seed >= 0 {
        r.seed(seed);
    } else {
        r.randomize();
    }
    let pool = d.pool(class);
    let quotas = [(1, 2, 8), (3, 4, 10), (5, 6, 7), (7, 99, 5)];
    let mut deck: Vec<CardId> = vec![];
    let mut counts = std::collections::HashMap::<CardId, usize>::new();
    for (lo, hi, n) in quotas {
        let bucket: Vec<CardId> = pool.iter().copied().filter(|&c| d.card(c).cost >= lo && d.card(c).cost <= hi).collect();
        let mut need = n;
        let mut tries = 0;
        while need > 0 && tries < 4000 && !bucket.is_empty() {
            tries += 1;
            let c = bucket[r.randi_range(0, bucket.len() as i64 - 1) as usize];
            let card = d.card(c);
            let w = (if card.class == class { 2.0 } else { 1.0 }) * (if card.kind == Kind::Minion { 3.0 } else { 1.0 });
            if r.randf() * 6.0 > w {
                continue;
            }
            if *counts.get(&c).unwrap_or(&0) >= card.max_copies() {
                continue;
            }
            deck.push(c);
            *counts.entry(c).or_insert(0) += 1;
            need -= 1;
        }
    }
    let mut guard = 0;
    while deck.len() < DECK_SIZE && guard < 20000 {
        guard += 1;
        let c = pool[r.randi_range(0, pool.len() as i64 - 1) as usize];
        if *counts.get(&c).unwrap_or(&0) < d.card(c).max_copies() {
            deck.push(c);
            *counts.entry(c).or_insert(0) += 1;
        }
    }
    deck
}
