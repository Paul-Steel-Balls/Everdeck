//! The rules, ported line for line from scripts/game_state.gd. Every
//! choice that uses the dice uses them in the same order as the game, so
//! the same seed plays the same game (checked by `lab parity`).
//! When the game's rules change, change this file the same way and rerun
//! the parity check.

use crate::data::*;
use crate::rng::Rng;
use std::sync::OnceLock;

pub static DB: OnceLock<Db> = OnceLock::new();
pub fn db() -> &'static Db {
    DB.get().expect("Db not loaded")
}

pub const STARTING_HP: i32 = 30;
pub const MAX_MANA: i32 = 10;
pub const MAX_BOARD: usize = 7;
pub const MAX_HAND: usize = 10;
pub const DECK_SIZE: usize = 30;
pub const HERO_POWER_COST: i32 = 2;

/// Seed for the bot's look-ahead copies. -1: a fresh seed each copy (the
/// game's behavior); >= 0: pinned (parity checks pin both sides).
pub static CLONE_SEED: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(-1);

/// Text play: the bot's look-ahead dice start from the game seed, so a
/// saved game replays the same way.
pub fn seed_clone_rng(s: i64) {
    CLONE_RNG.with(|r| r.borrow_mut().seed(s));
}

thread_local! {
    static CLONE_RNG: std::cell::RefCell<Rng> = std::cell::RefCell::new({ let mut r = Rng::new(0); r.randomize(); r });
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum T {
    None,
    Hero(usize),
    Minion(usize, i64),
}

impl T {
    pub fn player(&self) -> usize {
        match *self {
            T::Hero(p) | T::Minion(p, _) => p,
            T::None => 0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Minion {
    pub card: CardId,
    pub name_src: CardId,
    pub uid: i32,
    pub attack: i32,
    pub health: i32,
    pub max_health: i32,
    pub taunt: bool,
    pub can_attack: bool,
    pub attacks_left: i32,
    pub sick: bool,
    pub kw: u8,
    pub frozen: i32,
    pub silenced: bool,
    pub vibe_atk: i32,
    pub vibe_hp: i32,
}

impl Minion {
    pub fn has(&self, k: u8) -> bool {
        self.kw & k != 0
    }
    pub fn name(&self) -> String {
        let d = db();
        if self.card == d.generic {
            d.token_for(d.card(self.name_src)).1
        } else {
            d.card(self.card).name.clone()
        }
    }
}

#[derive(Clone, Debug)]
pub struct Player {
    pub hp: i32,
    pub mana: i32,
    pub max_mana: i32,
    pub deck: Vec<CardId>,
    pub hand: Vec<CardId>,
    pub board: Vec<Minion>,
    pub fatigue: i32,
    pub class: String,
    pub hero_power_used: bool,
    pub cards_played: i32,
    pub overload_next: i32,
    pub overload_locked: i32,
}

#[derive(Clone, Copy, Debug)]
struct Queued {
    owner: usize,
    uid: i32,
    card: CardId,
    trig: usize,
}

pub struct Game {
    pub players: [Player; 2],
    pub active: usize,
    pub winner: i32,
    pub turn_count: i32,
    pub rng: Rng,
    lethal_deferred: i32,
    next_uid: i32,
    src_uid: i32,
    src_card: Option<CardId>,
    queue: Vec<Queued>,
    in_trigger: bool,
    /// Text play mode: a running account of what happened (None in sims).
    pub log: Option<Vec<String>>,
}

#[derive(Clone)]
struct Dead {
    owner: usize,
    uid: i32,
    card: CardId,
    name: String,
    silenced: bool,
}

fn new_player(deck: &[CardId], class: &str) -> Player {
    Player {
        hp: STARTING_HP,
        mana: 0,
        max_mana: 0,
        deck: deck.to_vec(),
        hand: vec![],
        board: vec![],
        fatigue: 0,
        class: class.to_string(),
        hero_power_used: false,
        cards_played: 0,
        overload_next: 0,
        overload_locked: 0,
    }
}

impl Game {
    pub fn new(seed: i64, deck0: &[CardId], deck1: &[CardId], c0: &str, c1: &str) -> Game {
        let mut g = Game {
            players: [new_player(deck0, c0), new_player(deck1, c1)],
            active: 0,
            winner: -1,
            turn_count: 0,
            rng: Rng::new(seed),
            lethal_deferred: 0,
            next_uid: 0,
            src_uid: -1,
            src_card: None,
            queue: vec![],
            in_trigger: false,
            log: None,
        };
        g.setup();
        g
    }

    fn note(&mut self, s: String) {
        if let Some(l) = &mut self.log {
            l.push(s);
        }
    }

    /// A copy for look-ahead with its own dice (the bot can't peek).
    pub fn clone_for_ai(&self) -> Game {
        let pin = CLONE_SEED.load(std::sync::atomic::Ordering::Relaxed);
        let seed = if pin >= 0 {
            pin
        } else {
            CLONE_RNG.with(|r| {
                let mut b = r.borrow_mut();
                let x = b.randi();
                (x << 16) ^ b.randi()
            })
        };
        Game {
            players: self.players.clone(),
            active: self.active,
            winner: self.winner,
            turn_count: self.turn_count,
            rng: Rng::new(seed),
            lethal_deferred: 0,
            next_uid: self.next_uid,
            src_uid: -1,
            src_card: None,
            queue: vec![],
            in_trigger: false,
            log: None,
        }
    }

    fn setup(&mut self) {
        self.shuffle(0);
        self.shuffle(1);
        for _ in 0..3 {
            self.draw(0, true);
        }
        for _ in 0..5 {
            self.draw(1, true);
        }
        let coin = db().coin;
        self.players[1].hand.push(coin);
        self.start_turn();
    }

    fn shuffle(&mut self, p: usize) {
        let n = self.players[p].deck.len();
        for i in (1..n).rev() {
            let j = self.rng.randi_range(0, i as i64) as usize;
            self.players[p].deck.swap(i, j);
        }
    }

    // --- Turn flow ---

    fn start_turn(&mut self) {
        self.turn_count += 1;
        let a = self.active;
        {
            let p = &mut self.players[a];
            p.max_mana = MAX_MANA.min(p.max_mana + 1);
            p.mana = p.max_mana;
            let owed = p.overload_next;
            p.overload_locked = owed;
            p.overload_next = 0;
            if owed > 0 {
                p.mana = 0.max(p.mana - owed);
            }
            p.hero_power_used = false;
            p.cards_played = 0;
            for m in p.board.iter_mut() {
                m.sick = false;
                m.can_attack = true;
                m.attacks_left = if m.has(KW_WINDFURY) { 2 } else { 1 };
            }
        }
        self.lethal_deferred += 1;
        self.queue_triggers(a, When::StartOfTurn, -1);
        self.settle();
        self.lethal_deferred -= 1;
        self.check_lethal();
        if self.winner != -1 {
            return;
        }
        self.draw(a, false);
    }

    pub fn end_turn(&mut self) {
        if self.winner != -1 {
            return;
        }
        let a = self.active;
        self.lethal_deferred += 1;
        self.queue_triggers(a, When::EndOfTurn, -1);
        self.settle();
        self.lethal_deferred -= 1;
        self.check_lethal();
        if self.winner != -1 {
            return;
        }
        for m in self.players[a].board.iter_mut() {
            if m.frozen > 0 {
                m.frozen -= 1;
            }
        }
        self.active = 1 - a;
        self.start_turn();
    }

    // --- Drawing ---

    fn draw(&mut self, p: usize, _initial: bool) {
        if self.players[p].deck.is_empty() {
            self.players[p].fatigue += 1;
            let f = self.players[p].fatigue;
            self.players[p].hp -= f;
            self.note(format!("P{} has no cards left: {} damage.", p + 1, f));
            self.check_lethal();
            return;
        }
        let c = self.players[p].deck.remove(0);
        if self.players[p].hand.len() >= MAX_HAND {
            let n = db().card(c).name.clone();
            self.note(format!("P{}'s hand is full: {} burned.", p + 1, n));
        } else {
            self.players[p].hand.push(c);
        }
    }

    pub fn draw_cards(&mut self, p: usize, n: i32) {
        for _ in 0..n {
            if self.winner != -1 {
                return;
            }
            self.draw(p, false);
        }
    }

    // --- Playing cards ---

    pub fn can_play(&self, p: usize, hi: usize) -> bool {
        if p != self.active || self.winner != -1 {
            return false;
        }
        let pl = &self.players[p];
        if hi >= pl.hand.len() {
            return false;
        }
        let c = db().card(pl.hand[hi]);
        if pl.mana < c.cost {
            return false;
        }
        if c.kind == Kind::Minion && pl.board.len() >= MAX_BOARD {
            return false;
        }
        true
    }

    pub fn play_card(&mut self, p: usize, hi: usize, target: T) -> bool {
        if !self.can_play(p, hi) {
            return false;
        }
        let d = db();
        let cid = self.players[p].hand[hi];
        let card = d.card(cid);
        if card.kind == Kind::Spell && requires_player_target(card, false) {
            if target == T::None || !self.is_valid_target(p, card.target, target, false, -1) {
                return false;
            }
        }
        let hand_before = self.players[p].hand.len() as i32;
        self.players[p].hand.remove(hi);
        self.players[p].mana -= card.cost;
        self.note(format!("P{} plays {}.", p + 1, card.name));
        self.lethal_deferred += 1;
        if card.kind == Kind::Minion {
            self.summon(p, cid, cid, true);
            let src_idx = self.players[p].board.len() as i64 - 1;
            if card.effect != Eff::None {
                if !requires_player_target(card, true) || self.is_valid_target(p, card.target, target, true, src_idx) {
                    let src_uid = self.players[p].board[src_idx as usize].uid;
                    let (pu, pc) = (self.src_uid, self.src_card);
                    self.src_uid = src_uid;
                    self.src_card = Some(cid);
                    let tok = d.token_for(card);
                    self.resolve(p, card.effect, card.effect_value, target, hand_before, Some(tok.0), cid);
                    self.src_uid = pu;
                    self.src_card = pc;
                } else {
                    self.note("  (its Entrance has no target)".into());
                }
            }
        } else {
            let (pu, pc) = (self.src_uid, self.src_card);
            self.src_uid = -1;
            self.src_card = Some(cid);
            self.resolve(p, card.effect, card.effect_value, target, -1, None, cid);
            if card.effect2 != Eff::None {
                if card.e2_target == Tgt::None || self.is_valid_target(p, card.e2_target, target, false, -1) {
                    self.resolve(p, card.effect2, card.e2_value, target, -1, None, cid);
                }
            }
            self.src_uid = pu;
            self.src_card = pc;
        }
        self.players[p].cards_played += 1;
        if card.overload > 0 {
            self.players[p].overload_next += card.overload;
        }
        let mut played_uid = -1;
        if card.kind == Kind::Minion && !self.players[p].board.is_empty() {
            played_uid = self.players[p].board.last().unwrap().uid;
        }
        self.queue_triggers(p, When::FriendlyCardPlayed, played_uid);
        if card.kind == Kind::Spell {
            self.queue_triggers(p, When::FriendlyTrickPlayed, -1);
        }
        self.settle();
        self.lethal_deferred -= 1;
        self.check_lethal();
        true
    }

    /// name_src: the card whose token name a generic token shows.
    fn summon(&mut self, p: usize, cid: CardId, name_src: CardId, sick: bool) {
        if self.players[p].board.len() >= MAX_BOARD {
            return;
        }
        let c = db().card(cid);
        let charge = c.has(KW_CHARGE);
        let m = Minion {
            card: cid,
            name_src,
            uid: self.next_uid,
            attack: c.attack,
            health: c.health,
            max_health: c.health,
            taunt: c.has(KW_TAUNT),
            can_attack: charge,
            attacks_left: if charge { if c.has(KW_WINDFURY) { 2 } else { 1 } } else { 0 },
            sick: sick && !charge,
            kw: c.kw & (KW_SHIELD | KW_STEALTH | KW_WINDFURY | KW_POISON | KW_LIFESTEAL),
            frozen: 0,
            silenced: false,
            vibe_atk: 0,
            vibe_hp: 0,
        };
        self.next_uid += 1;
        let uid = m.uid;
        self.players[p].board.push(m);
        self.queue_triggers(p, When::FriendlySummon, uid);
        self.refresh_vibes();
    }

    // --- Signature Moves ---

    pub fn hero_power(&self, p: usize) -> Option<&'static Power> {
        db().powers.get(&self.players[p].class)
    }

    pub fn can_use_hero_power(&self, p: usize, target: T) -> bool {
        if p != self.active || self.winner != -1 {
            return false;
        }
        let pl = &self.players[p];
        if pl.hero_power_used || pl.mana < HERO_POWER_COST {
            return false;
        }
        let Some(hp) = self.hero_power(p) else { return false };
        if hp.effect == Eff::SummonToken && pl.board.len() >= MAX_BOARD {
            return false;
        }
        if hp.target == Tgt::FriendlyMinion {
            if target == T::None || !self.is_valid_target(p, Tgt::FriendlyMinion, target, false, -1) {
                return false;
            }
        }
        true
    }

    pub fn hero_power_target_options(&self, p: usize) -> Vec<T> {
        match self.hero_power(p) {
            Some(hp) if hp.target == Tgt::FriendlyMinion => (0..self.players[p].board.len()).map(|i| T::Minion(p, i as i64)).collect(),
            _ => vec![],
        }
    }

    pub fn use_hero_power(&mut self, p: usize, target: T) -> bool {
        if !self.can_use_hero_power(p, target) {
            return false;
        }
        let hp = self.hero_power(p).unwrap();
        self.players[p].mana -= HERO_POWER_COST;
        self.players[p].hero_power_used = true;
        self.lethal_deferred += 1;
        let mut use_target = target;
        if hp.target == Tgt::EnemyHero {
            use_target = T::Hero(1 - p);
        }
        let tok = if hp.effect == Eff::SummonToken { Some(db().deckhand) } else { None };
        self.note(format!("P{} uses {}.", p + 1, hp.name));
        let (pu, pc) = (self.src_uid, self.src_card);
        self.src_uid = -1;
        self.src_card = None;
        let ns = tok.unwrap_or(db().deckhand);
        self.resolve(p, hp.effect, hp.value, use_target, -1, tok, ns);
        self.src_uid = pu;
        self.src_card = pc;
        self.settle();
        self.lethal_deferred -= 1;
        self.check_lethal();
        true
    }

    // --- Effects ---

    /// token: the token card to summon (None = Kevin); name_src: whose
    /// token name a generic token shows.
    #[allow(clippy::too_many_arguments)]
    fn resolve(&mut self, p: usize, eff: Eff, value: i32, target: T, hand_before: i32, token: Option<CardId>, name_src: CardId) {
        let d = db();
        match eff {
            Eff::Damage => self.deal_damage_to_target(target, value),
            Eff::GainMana => self.players[p].mana = MAX_MANA.min(self.players[p].mana + value),
            Eff::HealHero => self.heal_hero(p, value),
            Eff::HealDraw => {
                self.heal_hero(p, value);
                self.draw_cards(p, 1);
            }
            Eff::Draw => self.draw_cards(p, value),
            Eff::DrawSelfDamage => {
                self.draw_cards(p, 1);
                self.players[p].hp -= value;
            }
            Eff::SummonToken => {
                let t = token.unwrap_or(d.squireling);
                self.summon(p, t, name_src, true);
            }
            Eff::DamageAllEnemyMinions => {
                let src = self.source_minion();
                let uids: Vec<i32> = self.players[1 - p].board.iter().map(|m| m.uid).collect();
                for u in uids {
                    self.hit_minion_uid(1 - p, u, value, src);
                }
            }
            Eff::DamageAllMinions => {
                let src = self.source_minion();
                for pl in 0..2 {
                    let uids: Vec<i32> = self.players[pl].board.iter().map(|m| m.uid).collect();
                    for u in uids {
                        self.hit_minion_uid(pl, u, value, src);
                    }
                }
            }
            Eff::Destroy => self.destroy_target(target),
            Eff::DestroyDamaged => {
                for m in self.players[1 - p].board.iter_mut() {
                    if m.health < m.max_health && m.health > 0 {
                        m.health = 0;
                    }
                }
            }
            Eff::RandomMinionDamage => {
                self.random_minion_damage(p);
                self.queue_triggers(p, When::RandomFired, -1);
            }
            Eff::RandomEnemyDamage => {
                let t = self.random_enemy_character(p);
                self.deal_damage_to_target(t, value);
                self.queue_triggers(p, When::RandomFired, -1);
            }
            Eff::StealWeak => self.steal_weak(p, value),
            Eff::SwapHands => {
                let (a, b) = self.players.split_at_mut(1);
                std::mem::swap(&mut a[0].hand, &mut b[0].hand);
                self.note("Hands swapped!".into());
            }
            Eff::CoinFlip => {
                self.queue_triggers(p, When::RandomFired, -1);
                let heads = self.rng.randf() < 0.5;
                if heads {
                    self.note("Coin flip: heads, draw 2.".into());
                    self.draw_cards(p, 2);
                } else {
                    self.note("Coin flip: tails, draw 1 and take 2.".into());
                    self.draw_cards(p, 1);
                    self.players[p].hp -= 2;
                }
            }
            Eff::BuffFriendly => self.buff_target(target, value),
            Eff::BuffAllFriendly => {
                for i in 0..self.players[p].board.len() {
                    self.apply_buff(p, i, value);
                }
            }
            Eff::DamagePerCardPlayed => {
                let mut n = self.players[p].cards_played;
                if d.payoff_cap >= 0 {
                    n = n.min(d.payoff_cap);
                }
                let dmg = value * 2 * n;
                if dmg > 0 {
                    let src = self.source_minion();
                    self.hit_hero(1 - p, dmg, src);
                }
            }
            Eff::DamagePerHandCard => {
                let count = if hand_before >= 0 { hand_before } else { self.players[p].hand.len() as i32 };
                let dmg = value * count;
                if dmg > 0 {
                    let src = self.source_minion();
                    self.hit_hero(1 - p, dmg, src);
                }
            }
            Eff::DamageSplit => {
                for _ in 0..value {
                    let t = self.random_enemy_character(p);
                    self.deal_damage_to_target(t, 1);
                }
                self.queue_triggers(p, When::RandomFired, -1);
            }
            Eff::Recruit => self.recruit(p, value),
            Eff::SwapStats => self.swap_stats(p),
            Eff::BuffAttack => {
                if let Some((o, i)) = self.target_minion(target) {
                    self.players[o].board[i].attack += value;
                    let u = self.players[o].board[i].uid;
                    self.queue_triggers(o, When::FriendlyBuffed, u);
                }
            }
            Eff::BuffHealth => {
                if let Some((o, i)) = self.target_minion(target) {
                    self.players[o].board[i].max_health += value;
                    self.players[o].board[i].health += value;
                    let u = self.players[o].board[i].uid;
                    self.queue_triggers(o, When::FriendlyBuffed, u);
                }
            }
            Eff::Freeze => {
                if let Some((o, i)) = self.target_minion(target) {
                    self.players[o].board[i].frozen = if o == self.active { 2 } else { 1 };
                }
            }
            Eff::Silence => {
                if let Some((o, i)) = self.target_minion(target) {
                    self.silence(o, i);
                }
            }
            Eff::SummonTokens => {
                for _ in 0..value.max(1) {
                    let t = token.unwrap_or(d.squireling);
                    self.summon(p, t, name_src, true);
                }
            }
            Eff::None | Eff::Unknown => {}
        }
    }

    fn apply_buff(&mut self, owner: usize, i: usize, n: i32) {
        let m = &mut self.players[owner].board[i];
        m.attack += n;
        m.max_health += n;
        m.health += n;
        let u = m.uid;
        self.queue_triggers(owner, When::FriendlyBuffed, u);
    }

    fn buff_target(&mut self, target: T, value: i32) {
        if let T::Minion(o, i) = target {
            if i < self.players[o].board.len() as i64 {
                self.apply_buff(o, i as usize, value);
            }
        }
    }

    fn deal_damage_to_target(&mut self, target: T, amount: i32) {
        match target {
            T::None => {}
            T::Hero(o) => {
                let src = self.source_minion();
                self.hit_hero(o, amount, src);
            }
            T::Minion(o, i) => {
                if i < self.players[o].board.len() as i64 {
                    let src = self.source_minion();
                    let u = self.players[o].board[i as usize].uid;
                    self.hit_minion_uid(o, u, amount, src);
                }
            }
        }
    }

    fn destroy_target(&mut self, target: T) {
        if let T::Minion(o, i) = target {
            if i < self.players[o].board.len() as i64 {
                self.players[o].board[i as usize].health = 0;
            }
        }
    }

    fn random_enemy_character(&mut self, p: usize) -> T {
        let e = 1 - p;
        let n = self.players[e].board.len() as i64 + 1;
        let pick = self.rng.randi_range(0, n - 1);
        if pick < self.players[e].board.len() as i64 {
            T::Minion(e, pick)
        } else {
            T::Hero(e)
        }
    }

    fn random_minion_damage(&mut self, p: usize) {
        let e = 1 - p;
        let dmg = self.rng.randi_range(2, 5) as i32;
        let src = self.source_minion();
        if self.players[e].board.is_empty() {
            self.hit_hero(e, dmg, src);
        } else {
            let idx = self.rng.randi_range(0, self.players[e].board.len() as i64 - 1) as usize;
            let u = self.players[e].board[idx].uid;
            self.hit_minion_uid(e, u, dmg, src);
        }
    }

    fn steal_weak(&mut self, p: usize, max_attack: i32) {
        let e = 1 - p;
        let cands: Vec<usize> = (0..self.players[e].board.len()).filter(|&i| self.players[e].board[i].attack <= max_attack).collect();
        if cands.is_empty() || self.players[p].board.len() >= MAX_BOARD {
            return;
        }
        let idx = cands[self.rng.randi_range(0, cands.len() as i64 - 1) as usize];
        let mut m = self.players[e].board.remove(idx);
        m.can_attack = false;
        m.sick = true;
        m.attacks_left = 0;
        self.note(format!("P{} steals {}.", p + 1, m.name()));
        self.players[p].board.push(m);
        self.refresh_vibes();
    }

    fn recruit(&mut self, p: usize, max_cost: i32) {
        if self.players[p].board.len() >= MAX_BOARD {
            return;
        }
        let d = db();
        let cands: Vec<usize> = (0..self.players[p].deck.len())
            .filter(|&i| {
                let c = d.card(self.players[p].deck[i]);
                c.kind == Kind::Minion && c.cost <= max_cost
            })
            .collect();
        if cands.is_empty() {
            return;
        }
        let pick = cands[self.rng.randi_range(0, cands.len() as i64 - 1) as usize];
        let cid = self.players[p].deck.remove(pick);
        self.note(format!("P{} recruits {}.", p + 1, d.card(cid).name));
        self.summon(p, cid, cid, true);
    }

    fn swap_stats(&mut self, p: usize) {
        let e = 1 - p;
        if self.players[e].board.is_empty() {
            return;
        }
        let idx = self.rng.randi_range(0, self.players[e].board.len() as i64 - 1) as usize;
        set_vibe(&mut self.players[e].board[idx], 0, 0);
        let m = &mut self.players[e].board[idx];
        let old = m.attack;
        m.attack = m.health;
        m.health = old;
        m.max_health = old;
        self.refresh_vibes();
    }

    // --- Deaths and Final Bows ---

    fn collect_dead(&mut self) -> Vec<Dead> {
        let mut out = vec![];
        for p in [self.active, 1 - self.active] {
            let board = &mut self.players[p].board;
            let mut i = 0;
            let mut dead = vec![];
            while i < board.len() {
                if board[i].health <= 0 {
                    dead.push(i);
                }
                i += 1;
            }
            for &i in &dead {
                let m = &board[i];
                out.push(Dead { owner: p, uid: m.uid, card: m.card, name: String::new(), silenced: m.silenced });
            }
            for &i in dead.iter().rev() {
                board.remove(i);
            }
        }
        if self.log.is_some() {
            for d in out.iter_mut() {
                d.name = db().card(d.card).name.clone();
            }
            let names: Vec<String> = out.iter().map(|d| d.name.clone()).collect();
            for n in names {
                self.note(format!("  {} dies.", n));
            }
        }
        if !out.is_empty() {
            self.refresh_vibes();
        }
        out
    }

    fn process_deaths(&mut self) {
        let mut pending = self.collect_dead();
        while !pending.is_empty() {
            let batch = std::mem::take(&mut pending);
            for dd in batch {
                self.queue_triggers(dd.owner, When::FriendlyCrewDied, -1);
                self.resolve_deathrattle(&dd);
            }
            pending.extend(self.collect_dead());
        }
    }

    fn resolve_deathrattle(&mut self, dd: &Dead) {
        let d = db();
        let card = d.card(dd.card);
        if dd.silenced || card.deathrattle == Eff::None {
            return;
        }
        let Some(target) = self.deathrattle_target(dd.owner, card.deathrattle, card.dr_target) else {
            return;
        };
        self.note(format!("  Final Bow: {}.", card.name));
        let (pu, pc) = (self.src_uid, self.src_card);
        self.src_uid = dd.uid;
        self.src_card = Some(dd.card);
        let tok = d.token_for(card);
        self.resolve(dd.owner, card.deathrattle, card.dr_value, target, -1, Some(tok.0), dd.card);
        self.src_uid = pu;
        self.src_card = pc;
    }

    /// Random targets for Final Bows and triggers. None = fizzle.
    fn deathrattle_target(&mut self, owner: usize, eff: Eff, tgt: Tgt) -> Option<T> {
        let foe = 1 - owner;
        match eff {
            Eff::Destroy => {
                if self.players[foe].board.is_empty() {
                    return None;
                }
                let i = self.rng.randi_range(0, self.players[foe].board.len() as i64 - 1);
                return Some(T::Minion(foe, i));
            }
            Eff::SwapStats => {
                if self.players[foe].board.is_empty() {
                    return None;
                }
                return Some(T::None);
            }
            _ => {}
        }
        match tgt {
            Tgt::AnyEnemy => Some(self.random_enemy_character(owner)),
            Tgt::EnemyMinion => {
                if self.players[foe].board.is_empty() {
                    return None;
                }
                let i = self.rng.randi_range(0, self.players[foe].board.len() as i64 - 1);
                Some(T::Minion(foe, i))
            }
            Tgt::FriendlyMinion => {
                if self.players[owner].board.is_empty() {
                    return None;
                }
                let i = self.rng.randi_range(0, self.players[owner].board.len() as i64 - 1);
                Some(T::Minion(owner, i))
            }
            Tgt::EnemyHero => Some(T::Hero(foe)),
            _ => Some(T::None),
        }
    }

    // --- Combat ---

    pub fn valid_attack_targets(&self, p: usize) -> Vec<T> {
        let e = 1 - p;
        let b = &self.players[e].board;
        let taunts: Vec<T> = (0..b.len()).filter(|&i| b[i].taunt && !b[i].has(KW_STEALTH)).map(|i| T::Minion(e, i as i64)).collect();
        if !taunts.is_empty() {
            return taunts;
        }
        let mut out: Vec<T> = (0..b.len()).filter(|&i| !b[i].has(KW_STEALTH)).map(|i| T::Minion(e, i as i64)).collect();
        out.push(T::Hero(e));
        out
    }

    pub fn can_attack(&self, p: usize, bi: usize) -> bool {
        if p != self.active || self.winner != -1 {
            return false;
        }
        let b = &self.players[p].board;
        if bi >= b.len() {
            return false;
        }
        let m = &b[bi];
        m.can_attack && m.attack > 0 && m.frozen == 0
    }

    pub fn attack(&mut self, p: usize, bi: usize, target: T) -> bool {
        if !self.can_attack(p, bi) {
            return false;
        }
        if !self.valid_attack_targets(p).contains(&target) {
            return false;
        }
        {
            let a = &mut self.players[p].board[bi];
            a.attacks_left -= 1;
            a.can_attack = a.attacks_left > 0;
        }
        self.lethal_deferred += 1;
        if let T::Minion(o, i) = target {
            if i >= self.players[o].board.len() as i64 {
                self.lethal_deferred -= 1;
                return false;
            }
        }
        if self.log.is_some() {
            let an = self.players[p].board[bi].name();
            let tn = match target {
                T::Hero(_) => "the enemy Boss".to_string(),
                T::Minion(o, i) => self.players[o].board[i as usize].name(),
                T::None => String::new(),
            };
            self.note(format!("P{}'s {} attacks {}.", p + 1, an, tn));
        }
        if self.players[p].board[bi].has(KW_STEALTH) {
            self.players[p].board[bi].kw &= !KW_STEALTH;
        }
        let attacker_uid = self.players[p].board[bi].uid;
        self.queue_self(p, bi, When::Attacks);
        let atk_snapshot = self.players[p].board[bi].clone();
        match target {
            T::Hero(o) => {
                let amt = atk_snapshot.attack;
                self.hit_hero(o, amt, Some((p, attacker_uid)));
            }
            T::Minion(o, i) => {
                let def = self.players[o].board[i as usize].clone();
                self.hit_minion_uid(o, def.uid, atk_snapshot.attack, Some((p, attacker_uid)));
                self.hit_minion_uid(p, attacker_uid, def.attack, Some((o, def.uid)));
            }
            T::None => {}
        }
        self.settle();
        self.lethal_deferred -= 1;
        self.check_lethal();
        true
    }

    // --- Targeting ---

    pub fn is_valid_target(&self, p: usize, tt: Tgt, target: T, is_battlecry: bool, src_idx: i64) -> bool {
        match (tt, target) {
            (_, T::None) => false,
            (Tgt::AnyEnemy, T::Hero(o)) => o == 1 - p,
            (Tgt::AnyEnemy, T::Minion(o, i)) | (Tgt::EnemyMinion, T::Minion(o, i)) => o == 1 - p && i < self.players[o].board.len() as i64 && !self.hidden(target),
            (Tgt::EnemyHero, T::Hero(o)) => o == 1 - p,
            (Tgt::FriendlyMinion, T::Minion(o, i)) => {
                if o != p || i >= self.players[p].board.len() as i64 {
                    return false;
                }
                !(is_battlecry && src_idx >= 0 && i == src_idx)
            }
            _ => false,
        }
    }

    pub fn card_target_options(&self, p: usize, card: &Card) -> Vec<T> {
        if card.effect == Eff::SwapStats {
            return vec![];
        }
        let mut tt = card.target;
        if tt == Tgt::None && card.kind == Kind::Spell {
            tt = card.e2_target;
        }
        let e = 1 - p;
        match tt {
            Tgt::AnyEnemy => {
                let mut out: Vec<T> = (0..self.players[e].board.len()).filter(|&i| !self.players[e].board[i].has(KW_STEALTH)).map(|i| T::Minion(e, i as i64)).collect();
                out.push(T::Hero(e));
                out
            }
            Tgt::EnemyMinion => (0..self.players[e].board.len()).filter(|&i| !self.players[e].board[i].has(KW_STEALTH)).map(|i| T::Minion(e, i as i64)).collect(),
            Tgt::FriendlyMinion => (0..self.players[p].board.len()).map(|i| T::Minion(p, i as i64)).collect(),
            _ => vec![],
        }
    }

    fn hidden(&self, t: T) -> bool {
        if let T::Minion(o, i) = t {
            let b = &self.players[o].board;
            return i >= 0 && (i as usize) < b.len() && b[i as usize].has(KW_STEALTH);
        }
        false
    }

    fn target_minion(&self, t: T) -> Option<(usize, usize)> {
        if let T::Minion(o, i) = t {
            if i >= 0 && (i as usize) < self.players[o].board.len() {
                return Some((o, i as usize));
            }
        }
        None
    }

    // --- Damage, healing, keywords ---

    /// The Crew member whose effect is resolving: (owner, uid).
    fn source_minion(&self) -> Option<(usize, i32)> {
        if self.src_uid < 0 {
            return None;
        }
        for pl in 0..2 {
            if self.players[pl].board.iter().any(|m| m.uid == self.src_uid) {
                return Some((pl, self.src_uid));
            }
        }
        None
    }

    fn find(&self, owner: usize, uid: i32) -> Option<usize> {
        self.players[owner].board.iter().position(|m| m.uid == uid)
    }

    fn src_flags(&self, src: Option<(usize, i32)>) -> (bool, bool, Option<(usize, i32)>) {
        match src {
            Some((o, u)) => match self.find(o, u) {
                Some(i) => {
                    let m = &self.players[o].board[i];
                    (m.has(KW_POISON), m.has(KW_LIFESTEAL), Some((o, u)))
                }
                None => (false, false, None),
            },
            None => (false, false, None),
        }
    }

    fn hit_minion_uid(&mut self, owner: usize, uid: i32, amount: i32, src: Option<(usize, i32)>) -> i32 {
        if amount <= 0 {
            return 0;
        }
        let Some(i) = self.find(owner, uid) else { return 0 };
        // Read the source's keywords before the hit (an attacker is hit
        // second; its flags can't change in between).
        let (poison, lifesteal, src_live) = self.src_flags(src);
        if self.players[owner].board[i].has(KW_SHIELD) {
            self.players[owner].board[i].kw &= !KW_SHIELD;
            if self.log.is_some() {
                let n = self.players[owner].board[i].name();
                self.note(format!("  {}'s Stunt Double takes the hit.", n));
            }
            return 0;
        }
        self.players[owner].board[i].health -= amount;
        let alive = self.players[owner].board[i].health > 0;
        if alive {
            self.queue_self(owner, i, When::Damaged);
        }
        if src_live.is_some() {
            if poison && self.players[owner].board[i].health > 0 {
                self.players[owner].board[i].health = 0;
            }
            if lifesteal {
                self.lifesteal(src_live.unwrap(), amount);
            }
        }
        amount
    }

    fn hit_hero(&mut self, p: usize, amount: i32, src: Option<(usize, i32)>) {
        if amount <= 0 {
            return;
        }
        let (_, lifesteal, src_live) = self.src_flags(src);
        self.players[p].hp -= amount;
        if lifesteal {
            self.lifesteal(src_live.unwrap(), amount);
        }
    }

    fn lifesteal(&mut self, src: (usize, i32), amount: i32) {
        let (o, u) = src;
        if self.find(o, u).is_none() {
            return;
        }
        let (pu, pc) = (self.src_uid, self.src_card);
        self.src_uid = u;
        self.src_card = self.find(o, u).map(|i| self.players[o].board[i].card);
        self.heal_hero(o, amount);
        self.src_uid = pu;
        self.src_card = pc;
    }

    fn heal_hero(&mut self, p: usize, amount: i32) {
        let before = self.players[p].hp;
        self.players[p].hp = STARTING_HP.min(before + amount);
        if self.players[p].hp > before {
            self.queue_triggers(p, When::BossHealed, -1);
        }
    }

    // --- Triggers ---

    fn queue_triggers(&mut self, p: usize, when: When, exclude_uid: i32) {
        if self.in_trigger {
            return;
        }
        for i in 0..self.players[p].board.len() {
            if self.players[p].board[i].uid == exclude_uid {
                continue;
            }
            self.queue_self(p, i, when);
        }
    }

    fn queue_self(&mut self, p: usize, i: usize, when: When) {
        let m = &self.players[p].board[i];
        if self.in_trigger || m.health <= 0 || m.silenced {
            return;
        }
        let c = db().card(m.card);
        for (ti, t) in c.triggers.iter().enumerate() {
            if t.when == when {
                self.queue.push(Queued { owner: p, uid: m.uid, card: m.card, trig: ti });
            }
        }
    }

    fn flush_triggers(&mut self) {
        let mut fired = 0;
        let mut qi = 0;
        let d = db();
        while qi < self.queue.len() && fired < 60 && self.winner == -1 {
            let q = self.queue[qi];
            qi += 1;
            let Some(hi) = self.find(q.owner, q.uid) else { continue };
            let h = &self.players[q.owner].board[hi];
            if h.health <= 0 || h.silenced {
                continue;
            }
            fired += 1;
            let card = d.card(q.card);
            let t = &card.triggers[q.trig];
            let target = match t.target {
                Tgt::SelfT => Some(T::Minion(q.owner, hi as i64)),
                Tgt::FriendlyHero => Some(T::Hero(q.owner)),
                _ => self.deathrattle_target(q.owner, t.effect, t.target),
            };
            let Some(target) = target else { continue };
            self.note(format!("  {} triggers.", card.name));
            let (pu, pc) = (self.src_uid, self.src_card);
            self.src_uid = q.uid;
            self.src_card = Some(q.card);
            self.in_trigger = true;
            let tok = d.token_for(card);
            self.resolve(q.owner, t.effect, t.value, target, -1, Some(tok.0), q.card);
            self.in_trigger = false;
            self.src_uid = pu;
            self.src_card = pc;
        }
        self.queue.clear();
    }

    fn settle(&mut self) {
        for _ in 0..40 {
            self.refresh_vibes();
            self.flush_triggers();
            let any_dead = self.players.iter().any(|p| p.board.iter().any(|m| m.health <= 0));
            if !any_dead && self.queue.is_empty() {
                break;
            }
            if any_dead {
                self.process_deaths();
            }
        }
        self.refresh_vibes();
    }

    // --- Vibes ---

    fn refresh_vibes(&mut self) {
        let d = db();
        let mut sources: Vec<(usize, i32, &Vibe)> = vec![];
        let mut any_bonus = false;
        for pl in 0..2 {
            for m in &self.players[pl].board {
                if m.vibe_atk != 0 || m.vibe_hp != 0 {
                    any_bonus = true;
                }
                if m.health <= 0 || m.silenced {
                    continue;
                }
                if let Some(v) = &d.card(m.card).vibe {
                    sources.push((pl, m.uid, v));
                }
            }
        }
        if sources.is_empty() && !any_bonus {
            return;
        }
        for pl in 0..2 {
            for i in 0..self.players[pl].board.len() {
                let (mut a, mut h) = (0, 0);
                {
                    let m = &self.players[pl].board[i];
                    for &(so, su, v) in &sources {
                        let applies = match v.who {
                            VibeWho::OtherFriendly => pl == so && m.uid != su,
                            VibeWho::AllFriendly => pl == so,
                            VibeWho::FriendlyDeckhands => pl == so && m.uid != su && m.card == d.deckhand,
                            VibeWho::FriendlyTokens => pl == so && m.uid != su && d.is_token(m.card),
                            VibeWho::Enemy => pl != so,
                            VibeWho::Other => false,
                        };
                        if applies {
                            a += v.attack;
                            h += v.health;
                        }
                    }
                }
                set_vibe(&mut self.players[pl].board[i], a, h);
            }
        }
    }

    fn silence(&mut self, owner: usize, i: usize) {
        let d = db();
        let m = &mut self.players[owner].board[i];
        set_vibe(m, 0, 0);
        m.silenced = true;
        m.taunt = false;
        m.kw = 0;
        m.frozen = 0;
        if m.attacks_left > 1 {
            m.attacks_left = 1;
        }
        let c = d.card(m.card);
        m.attack = c.attack;
        let damage_taken = m.max_health - m.health;
        m.max_health = c.health;
        m.health = if damage_taken >= 0 { m.health.min(c.health) } else { c.health };
        self.refresh_vibes();
    }

    fn check_lethal(&mut self) {
        if self.lethal_deferred > 0 {
            return;
        }
        let (h0, h1) = (self.players[0].hp, self.players[1].hp);
        let mut nw = self.winner;
        if h0 <= 0 && h1 <= 0 {
            nw = 1 - self.active as i32;
        } else if h0 <= 0 {
            nw = 1;
        } else if h1 <= 0 {
            nw = 0;
        }
        if nw != -1 && self.winner == -1 {
            self.winner = nw;
            self.note(format!("Game over: P{} wins.", nw + 1));
        }
    }
}

fn set_vibe(m: &mut Minion, a: i32, h: i32) {
    let da = a - m.vibe_atk;
    let dh = h - m.vibe_hp;
    if da == 0 && dh == 0 {
        return;
    }
    if m.health <= 0 && dh > 0 {
        return;
    }
    m.attack = 0.max(m.attack + da);
    m.max_health += dh;
    if dh > 0 {
        m.health += dh;
    } else {
        m.health = m.health.min(m.max_health);
    }
    m.vibe_atk = a;
    m.vibe_hp = h;
}

/// Does this card's effect need a chosen target? (swap_stats is random.)
pub fn requires_player_target(c: &Card, _is_battlecry: bool) -> bool {
    if c.effect == Eff::SwapStats {
        return false;
    }
    c.target != Tgt::None
}
