//! Everdeck Lab: the game's rules and bot, text only, as fast as possible.
//! See lab/README.md for the commands.

mod ai;
mod data;
mod game;
mod json;
mod rng;
mod sim;
mod tools;

use std::collections::HashMap;

pub struct Args {
    pub cmd: String,
    pub pos: Vec<String>,
    pub kv: HashMap<String, String>,
}

impl Args {
    pub fn get(&self, k: &str, d: &str) -> String {
        self.kv.get(k).cloned().unwrap_or_else(|| d.to_string())
    }
    pub fn int(&self, k: &str, d: i64) -> i64 {
        self.kv.get(k).and_then(|v| v.parse().ok()).unwrap_or(d)
    }
    pub fn has(&self, k: &str) -> bool {
        self.kv.contains_key(k)
    }
}

fn parse_args() -> Args {
    let mut it = std::env::args().skip(1);
    let cmd = it.next().unwrap_or_else(|| "help".into());
    let mut pos = vec![];
    let mut kv = HashMap::new();
    let rest: Vec<String> = it.collect();
    let mut i = 0;
    while i < rest.len() {
        let a = &rest[i];
        if let Some(k) = a.strip_prefix("--") {
            if let Some((k2, v)) = k.split_once('=') {
                kv.insert(k2.to_string(), v.to_string());
            } else if i + 1 < rest.len() && !rest[i + 1].starts_with("--") {
                kv.insert(k.to_string(), rest[i + 1].clone());
                i += 1;
            } else {
                kv.insert(k.to_string(), "1".into());
            }
        } else {
            pos.push(a.clone());
        }
        i += 1;
    }
    Args { cmd, pos, kv }
}

fn main() {
    let args = parse_args();
    if args.cmd == "help" || args.cmd == "--help" {
        print!("{}", tools::HELP);
        return;
    }
    let here = std::env::current_exe().ok().and_then(|p| p.parent().map(|p| p.to_path_buf()));
    let default_rules = here
        .as_ref()
        .map(|p| p.join("../../data/rules.json"))
        .filter(|p| p.exists())
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "data/rules.json".into());
    let rules = args.get("rules", &default_rules);
    let mut db = match data::Db::load(&rules) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("can't load rules: {}", e);
            std::process::exit(2);
        }
    };
    if args.has("patch") {
        let path = args.get("patch", "");
        let txt = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {}", path, e));
        let p = json::J::parse(&txt).expect("patch is not JSON");
        let probs = db.apply_patch(&p);
        eprintln!("[lab] patch {} applied ({} problems)", path, probs.len());
        for pr in probs {
            eprintln!("  {}", pr);
        }
    }
    if args.has("plan") {
        ai::PLAN.store(args.int("plan", 0), std::sync::atomic::Ordering::Relaxed);
    }
    if args.has("plan-seat") {
        ai::PLAN_SEAT.store(args.int("plan-seat", -1), std::sync::atomic::Ordering::Relaxed);
    }
    if args.has("variant") {
        let _ = sim::VARIANT.set(args.get("variant", ""));
    }
    if args.has("clone-seed") {
        game::CLONE_SEED.store(args.int("clone-seed", -1), std::sync::atomic::Ordering::Relaxed);
    }
    if game::DB.set(db).is_err() {
        unreachable!();
    }
    tools::run(&args);
}
