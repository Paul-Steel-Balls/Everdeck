//! Cards, tokens and Signature Moves, read from lab/data/rules.json (the
//! game exports it: tools/lab_export.gd). A patch file can change any of
//! it in memory, the same format as the Godot sims' SIM_PATCH.

use crate::json::J;
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Minion,
    Spell,
}

/// Effect names, kept as the game spells them (the bot's "is this random"
/// check reads the words).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Eff {
    None,
    Damage,
    GainMana,
    HealHero,
    HealDraw,
    Draw,
    DrawSelfDamage,
    SummonToken,
    DamageAllEnemyMinions,
    DamageAllMinions,
    Destroy,
    DestroyDamaged,
    RandomMinionDamage,
    RandomEnemyDamage,
    StealWeak,
    SwapHands,
    CoinFlip,
    BuffFriendly,
    BuffAllFriendly,
    DamagePerCardPlayed,
    DamagePerHandCard,
    DamageSplit,
    Recruit,
    SwapStats,
    BuffAttack,
    BuffHealth,
    Freeze,
    Silence,
    SummonTokens,
    Unknown,
}

impl Eff {
    pub fn from(s: &str) -> Eff {
        match s {
            "" => Eff::None,
            "damage" => Eff::Damage,
            "gain_mana" => Eff::GainMana,
            "heal_hero" => Eff::HealHero,
            "heal_draw" => Eff::HealDraw,
            "draw" => Eff::Draw,
            "draw_self_damage" => Eff::DrawSelfDamage,
            "summon_token" => Eff::SummonToken,
            "damage_all_enemy_minions" => Eff::DamageAllEnemyMinions,
            "damage_all_minions" => Eff::DamageAllMinions,
            "destroy" => Eff::Destroy,
            "destroy_damaged" => Eff::DestroyDamaged,
            "random_minion_damage" => Eff::RandomMinionDamage,
            "random_enemy_damage" => Eff::RandomEnemyDamage,
            "steal_weak" => Eff::StealWeak,
            "swap_hands" => Eff::SwapHands,
            "coin_flip" => Eff::CoinFlip,
            "buff_friendly" => Eff::BuffFriendly,
            "buff_all_friendly" => Eff::BuffAllFriendly,
            "damage_per_card_played" => Eff::DamagePerCardPlayed,
            "damage_per_hand_card" => Eff::DamagePerHandCard,
            "damage_split" => Eff::DamageSplit,
            "recruit" => Eff::Recruit,
            "swap_stats" => Eff::SwapStats,
            "buff_attack" => Eff::BuffAttack,
            "buff_health" => Eff::BuffHealth,
            "freeze" => Eff::Freeze,
            "silence" => Eff::Silence,
            "summon_tokens" => Eff::SummonTokens,
            _ => Eff::Unknown,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tgt {
    None,
    AnyEnemy,
    EnemyMinion,
    EnemyHero,
    FriendlyMinion,
    SelfT,
    FriendlyHero,
    Other,
}

impl Tgt {
    pub fn from(s: &str) -> Tgt {
        match s {
            "none" | "" => Tgt::None,
            "any_enemy" => Tgt::AnyEnemy,
            "enemy_minion" => Tgt::EnemyMinion,
            "enemy_hero" => Tgt::EnemyHero,
            "friendly_minion" => Tgt::FriendlyMinion,
            "self" => Tgt::SelfT,
            "friendly_hero" => Tgt::FriendlyHero,
            _ => Tgt::Other,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum When {
    FriendlyTrickPlayed,
    FriendlyCardPlayed,
    FriendlySummon,
    FriendlyBuffed,
    BossHealed,
    FriendlyCrewDied,
    RandomFired,
    Attacks,
    Damaged,
    StartOfTurn,
    EndOfTurn,
    Other,
}

impl When {
    pub fn from(s: &str) -> When {
        match s {
            "friendly_trick_played" => When::FriendlyTrickPlayed,
            "friendly_card_played" => When::FriendlyCardPlayed,
            "friendly_summon" => When::FriendlySummon,
            "friendly_buffed" => When::FriendlyBuffed,
            "boss_healed" => When::BossHealed,
            "friendly_crew_died" => When::FriendlyCrewDied,
            "random_fired" => When::RandomFired,
            "attacks" => When::Attacks,
            "damaged" => When::Damaged,
            "start_of_turn" => When::StartOfTurn,
            "end_of_turn" => When::EndOfTurn,
            _ => When::Other,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Trig {
    pub when: When,
    pub effect: Eff,
    pub value: i32,
    pub target: Tgt,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VibeWho {
    OtherFriendly,
    AllFriendly,
    FriendlyDeckhands,
    FriendlyTokens,
    Enemy,
    Other,
}

#[derive(Clone, Debug)]
pub struct Vibe {
    pub attack: i32,
    pub health: i32,
    pub who: VibeWho,
}

pub const KW_TAUNT: u8 = 1;
pub const KW_CHARGE: u8 = 2;
pub const KW_SHIELD: u8 = 4;
pub const KW_STEALTH: u8 = 8;
pub const KW_WINDFURY: u8 = 16;
pub const KW_POISON: u8 = 32;
pub const KW_LIFESTEAL: u8 = 64;

#[derive(Clone, Debug)]
pub struct Card {
    pub id: String,
    pub name: String,
    pub class: String,
    pub cost: i32,
    pub kind: Kind,
    pub attack: i32,
    pub health: i32,
    pub kw: u8,
    pub effect: Eff,
    pub effect_name: String,
    pub effect_value: i32,
    pub target: Tgt,
    pub deathrattle: Eff,
    pub deathrattle_name: String,
    pub dr_value: i32,
    pub dr_target: Tgt,
    pub effect2: Eff,
    pub effect2_name: String,
    pub e2_value: i32,
    pub e2_target: Tgt,
    pub text: String,
    pub rarity: String,
    pub token: Option<(String, String)>,
    pub triggers: Vec<Trig>,
    pub vibe: Option<Vibe>,
    pub overload: i32,
}

impl Card {
    pub fn has(&self, k: u8) -> bool {
        self.kw & k != 0
    }
    pub fn max_copies(&self) -> usize {
        if self.rarity == "Legendary" {
            1
        } else {
            2
        }
    }
}

fn kw_bits(j: &J) -> u8 {
    let mut b = 0;
    for k in j.arr() {
        b |= match k.s().as_str() {
            "taunt" => KW_TAUNT,
            "charge" => KW_CHARGE,
            "shield" => KW_SHIELD,
            "stealth" => KW_STEALTH,
            "windfury" => KW_WINDFURY,
            "poison" => KW_POISON,
            "lifesteal" => KW_LIFESTEAL,
            _ => 0,
        };
    }
    b
}

fn card_from(j: &J) -> Card {
    let mut c = Card {
        id: j.get("id").s(),
        name: j.get("name").s(),
        class: if j.has("class") { j.get("class").s() } else { "neutral".into() },
        cost: j.get("cost").i() as i32,
        kind: if j.get("type").s() == "spell" { Kind::Spell } else { Kind::Minion },
        attack: j.get("attack").i() as i32,
        health: j.get("health").i() as i32,
        kw: kw_bits(j.get("keywords")),
        effect: Eff::None,
        effect_name: String::new(),
        effect_value: 0,
        target: Tgt::None,
        deathrattle: Eff::None,
        deathrattle_name: String::new(),
        dr_value: 0,
        dr_target: Tgt::None,
        effect2: Eff::None,
        effect2_name: String::new(),
        e2_value: 0,
        e2_target: Tgt::None,
        text: j.get("text").s(),
        rarity: if j.has("rarity") { j.get("rarity").s() } else { "Common".into() },
        token: None,
        triggers: vec![],
        vibe: None,
        overload: 0,
    };
    apply_fields(&mut c, j);
    c
}

/// Set every field the JSON object names (used for loading and patching).
fn apply_fields(c: &mut Card, j: &J) {
    let Some(m) = j.obj() else { return };
    for (k, v) in m {
        match k.as_str() {
            "name" => c.name = v.s(),
            "class" => c.class = v.s(),
            "cost" => c.cost = v.i() as i32,
            "type" => c.kind = if v.s() == "spell" { Kind::Spell } else { Kind::Minion },
            "attack" => c.attack = v.i() as i32,
            "health" => c.health = v.i() as i32,
            "keywords" => c.kw = kw_bits(v),
            "effect" => {
                c.effect_name = v.s();
                c.effect = Eff::from(&c.effect_name)
            }
            "effect_value" => c.effect_value = v.i() as i32,
            "target" => c.target = Tgt::from(&v.s()),
            "deathrattle" => {
                c.deathrattle_name = v.s();
                c.deathrattle = Eff::from(&c.deathrattle_name)
            }
            "deathrattle_value" => c.dr_value = v.i() as i32,
            "deathrattle_target" => c.dr_target = Tgt::from(&v.s()),
            "effect2" => {
                c.effect2_name = v.s();
                c.effect2 = Eff::from(&c.effect2_name)
            }
            "effect2_value" => c.e2_value = v.i() as i32,
            "effect2_target" => c.e2_target = Tgt::from(&v.s()),
            "text" => c.text = v.s(),
            "rarity" => c.rarity = v.s(),
            "token" => {
                c.token = if v.obj().map(|m| !m.is_empty()).unwrap_or(false) { Some((v.get("name").s(), v.get("art").s())) } else { None };
            }
            "overload" => c.overload = v.i() as i32,
            "triggers" => {
                c.triggers = v
                    .arr()
                    .iter()
                    .map(|t| Trig {
                        when: When::from(&t.get("when").s()),
                        effect: Eff::from(&t.get("effect").s()),
                        value: if t.has("value") { t.get("value").i() as i32 } else { 0 },
                        target: if t.has("target") { Tgt::from(&t.get("target").s()) } else { Tgt::None },
                    })
                    .collect()
            }
            "vibe" => {
                c.vibe = if v.obj().map(|m| !m.is_empty()).unwrap_or(false) {
                    Some(Vibe {
                        attack: v.get("attack").i() as i32,
                        health: v.get("health").i() as i32,
                        who: match (if v.has("who") { v.get("who").s() } else { "other_friendly".into() }).as_str() {
                            "other_friendly" => VibeWho::OtherFriendly,
                            "all_friendly" => VibeWho::AllFriendly,
                            "friendly_deckhands" => VibeWho::FriendlyDeckhands,
                            "friendly_tokens" => VibeWho::FriendlyTokens,
                            "enemy" => VibeWho::Enemy,
                            _ => VibeWho::Other,
                        },
                    })
                } else {
                    None
                }
            }
            _ => {}
        }
    }
}

#[derive(Clone, Debug)]
pub struct Power {
    pub name: String,
    pub text: String,
    pub effect: Eff,
    pub effect_name: String,
    pub value: i32,
    pub target: Tgt,
}

/// Card index: 0..n are the real cards, then the special ones.
pub type CardId = u16;

pub struct Db {
    pub cards: Vec<Card>,
    pub by_id: HashMap<String, CardId>,
    pub powers: HashMap<String, Power>,
    pub classes: Vec<String>,
    pub payoff_cap: i32,
    /// Every heal pays off: a heal at full Health still counts as "healed"
    /// for payoffs (patch "overheal": 0 = the old rule).
    pub overheal: bool,
    pub squireling: CardId,
    pub deckhand: CardId,
    pub generic: CardId,
    pub coin: CardId,
    pub n_real: usize,
    pub version: String,
}

impl Db {
    pub fn load(path: &str) -> Result<Db, String> {
        let txt = std::fs::read_to_string(path).map_err(|e| format!("{}: {}", path, e))?;
        let j = J::parse(&txt)?;
        let mut cards: Vec<Card> = j.get("cards").arr().iter().map(card_from).collect();
        let n_real = cards.len();
        let tk = j.get("tokens");
        let mut special = |name: &str, cards: &mut Vec<Card>| -> CardId {
            cards.push(card_from(tk.get(name)));
            (cards.len() - 1) as CardId
        };
        let squireling = special("squireling", &mut cards);
        let deckhand = special("deckhand", &mut cards);
        let generic = special("token", &mut cards);
        let coin = special("coin", &mut cards);
        let mut by_id = HashMap::new();
        for (i, c) in cards.iter().enumerate() {
            by_id.entry(c.id.clone()).or_insert(i as CardId);
        }
        let mut powers = HashMap::new();
        if let Some(m) = j.get("hero_powers").obj() {
            for (cls, p) in m {
                powers.insert(cls.clone(), power_from(p));
            }
        }
        Ok(Db {
            cards,
            by_id,
            powers,
            classes: j.get("classes").arr().iter().map(|x| x.s()).collect(),
            payoff_cap: if j.has("payoff_cap") { j.get("payoff_cap").i() as i32 } else { 3 },
            overheal: true,
            squireling,
            deckhand,
            generic,
            coin,
            n_real,
            version: j.get("version").s(),
        })
    }

    pub fn id(&self, s: &str) -> Option<CardId> {
        self.by_id.get(s).copied()
    }

    pub fn card(&self, i: CardId) -> &Card {
        &self.cards[i as usize]
    }

    pub fn is_token(&self, i: CardId) -> bool {
        i == self.deckhand || i == self.squireling || i == self.generic
    }

    /// Cards a class may put in a deck, in the game's order.
    pub fn pool(&self, class: &str) -> Vec<CardId> {
        (0..self.n_real).filter(|&i| self.cards[i].class == class || self.cards[i].class == "neutral").map(|i| i as CardId).collect()
    }

    /// The token a card summons: its "token" field, else "Summon a 1/1 X."
    /// in its text, else Kevin the Intern (CardDB.token_for).
    pub fn token_for(&self, c: &Card) -> (CardId, String) {
        if let Some((name, _)) = &c.token {
            if name == "Kevin, the Intern" {
                return (self.squireling, self.card(self.squireling).name.clone());
            }
            return (self.generic, name.clone());
        }
        if let Some(p) = c.text.find("Summon a 1/1 ") {
            let rest = &c.text[p + 13..];
            if let Some(dot) = rest.find('.') {
                if dot > 0 {
                    let name = &rest[..dot];
                    if name == "Kevin, the Intern" {
                        return (self.squireling, self.card(self.squireling).name.clone());
                    }
                    return (self.generic, name.to_string());
                }
            }
        }
        (self.squireling, self.card(self.squireling).name.clone())
    }

    /// A what-if patch, same format as SIM_PATCH: {"cards": {id: {field:
    /// value}}, "powers": {class: {...}}, "deckhand": {...}, "payoff_cap"}.
    pub fn apply_patch(&mut self, p: &J) -> Vec<String> {
        let mut problems = vec![];
        if let Some(m) = p.get("cards").obj() {
            for (id, ch) in m {
                match self.id(id) {
                    Some(i) => apply_fields(&mut self.cards[i as usize], ch),
                    None => problems.push(format!("no card {}", id)),
                }
            }
        }
        if let Some(m) = p.get("powers").obj() {
            for (cls, ch) in m {
                if let Some(pw) = self.powers.get_mut(cls) {
                    if let Some(o) = ch.obj() {
                        for (k, v) in o {
                            match k.as_str() {
                                "name" => pw.name = v.s(),
                                "text" => pw.text = v.s(),
                                "effect" => {
                                    pw.effect_name = v.s();
                                    pw.effect = Eff::from(&pw.effect_name)
                                }
                                "value" => pw.value = v.i() as i32,
                                "target" => pw.target = Tgt::from(&v.s()),
                                _ => {}
                            }
                        }
                    }
                } else {
                    problems.push(format!("no class {}", cls));
                }
            }
        }
        if p.has("deckhand") {
            let d = self.deckhand as usize;
            apply_fields(&mut self.cards[d], p.get("deckhand"));
        }
        if p.has("payoff_cap") {
            self.payoff_cap = p.get("payoff_cap").i() as i32;
        }
        if p.has("overheal") {
            self.overheal = p.get("overheal").i() != 0;
        }
        problems
    }
}

fn power_from(p: &J) -> Power {
    Power {
        name: p.get("name").s(),
        text: p.get("text").s(),
        effect: Eff::from(&p.get("effect").s()),
        effect_name: p.get("effect").s(),
        value: p.get("value").i() as i32,
        target: Tgt::from(&p.get("target").s()),
    }
}
