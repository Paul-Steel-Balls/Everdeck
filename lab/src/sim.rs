//! One bot-vs-bot game (tools/sim_lib.gd), plus the record it leaves.

use crate::ai::*;
use crate::data::*;
use crate::game::*;
use crate::json::*;

pub const TURN_CAP: i32 = 90;
pub const ACTION_CAP: i32 = 60;

pub struct Rec {
    pub a: String,
    pub b: String,
    pub seed: i64,
    pub w: i32,
    pub t: i32,
    pub hp: [i32; 2],
    pub d0: Vec<CardId>,
    pub d1: Vec<CardId>,
    pub p0: Vec<(CardId, i32)>,
    pub p1: Vec<(CardId, i32)>,
    pub pw: [i32; 2],
}

pub fn play(a: &str, b: &str, d0: &[CardId], d1: &[CardId], seed: i64, variant: &str) -> Rec {
    let mut ai = Ai::new(seed + 3);
    // The bot's look-ahead dice start from the game seed (unless pinned),
    // so a Lab run repeats exactly. The game itself uses fresh dice.
    if CLONE_SEED.load(std::sync::atomic::Ordering::Relaxed) < 0 {
        seed_clone_rng(seed.wrapping_mul(0x9E3779B1).wrapping_add(17));
    }
    let mut gs = Game::new(seed, d0, d1, a, b);
    apply_variant(&mut gs, variant);
    let mut played: [Vec<(CardId, i32)>; 2] = [vec![], vec![]];
    let mut powers = [0, 0];
    while gs.winner == -1 && gs.turn_count <= TURN_CAP {
        let p = gs.active;
        let mut n = 0;
        while gs.winner == -1 && n < ACTION_CAP {
            n += 1;
            let act = ai.next_action(&gs, p);
            if act == Act::End {
                break;
            }
            let cid = if let Act::Play(hi, _) = act { Some(gs.players[p].hand[hi]) } else { None };
            if !apply(&mut gs, p, act) {
                break;
            }
            if let Some(c) = cid {
                played[p].push((c, gs.turn_count));
            } else if matches!(act, Act::Power(_)) {
                powers[p] += 1;
            }
        }
        if gs.winner != -1 {
            break;
        }
        gs.end_turn();
    }
    let [p0, p1] = played;
    Rec { a: a.into(), b: b.into(), seed, w: gs.winner, t: gs.turn_count, hp: [gs.players[0].hp, gs.players[1].hp], d0: d0.to_vec(), d1: d1.to_vec(), p0, p1, pw: powers }
}

/// The going-first what-ifs (sim_lib.gd _variant).
pub fn apply_variant(gs: &mut Game, v: &str) {
    match v {
        "p2card" => {
            if let Some(c) = gs.players[1].deck.pop() {
                gs.players[1].hand.push(c);
            }
        }
        "p1nodraw" => {
            if gs.players[0].hand.len() > 3 {
                let c = gs.players[0].hand.pop().unwrap();
                gs.players[0].deck.insert(0, c);
            }
        }
        "coin2" => gs.players[1].hand.push(db().coin),
        "p2minus" => {
            let coin = db().coin;
            if let Some(i) = gs.players[1].hand.iter().rposition(|&c| c != coin) {
                let c = gs.players[1].hand.remove(i);
                gs.players[1].deck.insert(0, c);
            }
        }
        "nocoin" => {
            let coin = db().coin;
            if let Some(i) = gs.players[1].hand.iter().position(|&c| c == coin) {
                gs.players[1].hand.remove(i);
            }
        }
        "p2hp3" => gs.players[1].hp += 3,
        _ => {}
    }
}

fn ids(v: &[CardId]) -> J {
    J::Arr(v.iter().map(|&c| st(&db().card(c).id)).collect())
}

impl Rec {
    pub fn to_json(&self) -> J {
        let pl = |v: &Vec<(CardId, i32)>| J::Arr(v.iter().map(|&(c, t)| J::Arr(vec![st(&db().card(c).id), num(t as i64)])).collect());
        obj(vec![
            ("a", st(&self.a)),
            ("b", st(&self.b)),
            ("seed", num(self.seed)),
            ("w", num(self.w as i64)),
            ("t", num(self.t as i64)),
            ("hp", J::Arr(vec![num(self.hp[0] as i64), num(self.hp[1] as i64)])),
            ("d0", ids(&self.d0)),
            ("d1", ids(&self.d1)),
            ("p0", pl(&self.p0)),
            ("p1", pl(&self.p1)),
            ("pw", J::Arr(vec![num(self.pw[0] as i64), num(self.pw[1] as i64)])),
        ])
    }
    /// Score for the class that went first (`a`): 1 win, 0.5 draw, 0 loss.
    pub fn score_a(&self) -> f64 {
        match self.w {
            0 => 1.0,
            1 => 0.0,
            _ => 0.5,
        }
    }
}
