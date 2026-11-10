//! The Lab's commands: meta, search, pick, play, cards.

use crate::ai::*;
use crate::data::*;
use crate::game::*;
use crate::json::*;
use crate::rng::Rng;
use crate::sim::*;
use crate::Args;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

pub const HELP: &str = "Everdeck Lab: the game's rules and bot, text only.

  lab meta   [--games 300] [--seed 1] [--decks f.json] [--classes a,b] [--hero c]
             [--variant v] [--threads 2] [--out games.jsonl]
      Every ordered pair of Bosses plays --games games. Prints win rates.
  lab search --class barnacle [--iters 100] [--games 160] [--field f.json]
             [--start f.json] [--seed 7] [--out deck.json]
      Hill-climb one Boss's 30-card list against the field.
  lab pick   --pool f.json [--games 300] [--out dir]
      Each Boss plays its best list from the pool; prints the meta.
  lab play   new --me barnacle --vs grunk [--seed 1] [--second] --save g.json
  lab play   show|move N|end --save g.json
      Play against the bot by text. Moves are numbered on screen.
  lab cards  [--class barnacle] [--find text]

  Every command takes --patch f.json (what-if card changes, the SIM_PATCH
  format), --rules f.json (default lab/data/rules.json) and
  --clone-seed N (pin the bot's look-ahead dice, for parity checks).
";

pub fn run(a: &Args) {
    match a.cmd.as_str() {
        "meta" => meta(a),
        "search" => search(a),
        "pick" => pick(a),
        "play" => play_cmd(a),
        "cards" => cards(a),
        "bench" => bench(a),
        _ => {
            eprintln!("unknown command {}\n", a.cmd);
            print!("{}", HELP);
        }
    }
}

fn threads(a: &Args) -> usize {
    a.int("threads", std::thread::available_parallelism().map(|n| n.get() as i64).unwrap_or(2)) as usize
}

fn classes(a: &Args) -> Vec<String> {
    if a.has("classes") {
        a.get("classes", "").split(',').map(|s| s.to_string()).collect()
    } else {
        db().classes.clone()
    }
}

fn deck_ids(j: &J) -> Vec<CardId> {
    j.arr().iter().filter_map(|x| db().id(&x.s())).collect()
}

/// {class: [ids]} or {class: [[ids], ...]} -> class -> lists.
pub fn load_lists(path: &str) -> HashMap<String, Vec<Vec<CardId>>> {
    let txt = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {}", path, e));
    let j = J::parse(&txt).expect("not JSON");
    let mut out = HashMap::new();
    if let Some(m) = j.obj() {
        for (k, v) in m {
            let lists: Vec<Vec<CardId>> = if v.arr().first().map(|x| matches!(x, J::Arr(_))).unwrap_or(false) { v.arr().iter().map(deck_ids).collect() } else { vec![deck_ids(v)] };
            out.insert(k.clone(), lists);
        }
    }
    out
}

/// Run jobs on all cores; results come back in job order.
fn par_map<T: Send + 'static, R: Send + 'static>(jobs: Vec<T>, n: usize, f: Arc<dyn Fn(&T) -> R + Send + Sync>) -> Vec<R> {
    let total = jobs.len();
    let jobs = Arc::new(Mutex::new(jobs.into_iter().enumerate().collect::<Vec<_>>()));
    let out = Arc::new(Mutex::new((0..total).map(|_| None).collect::<Vec<Option<R>>>()));
    let mut hs = vec![];
    for _ in 0..n.max(1) {
        let jobs = jobs.clone();
        let out = out.clone();
        let f = f.clone();
        hs.push(std::thread::spawn(move || loop {
            let job = jobs.lock().unwrap().pop();
            let Some((i, j)) = job else { break };
            let r = f(&j);
            out.lock().unwrap()[i] = Some(r);
        }));
    }
    for h in hs {
        h.join().unwrap();
    }
    Arc::try_unwrap(out).ok().unwrap().into_inner().unwrap().into_iter().map(|x| x.unwrap()).collect()
}

// --- meta ---

struct Job {
    a: String,
    b: String,
    seed: i64,
    d0: Vec<CardId>,
    d1: Vec<CardId>,
}

fn meta(a: &Args) {
    let games = a.int("games", 20);
    let base = a.int("seed", 1);
    let cls = classes(a);
    let fixed = if a.has("decks") { load_lists(&a.get("decks", "")) } else { HashMap::new() };
    let hero = a.get("hero", "");
    let variant = a.get("variant", "");
    let mut jobs = vec![];
    let mut k: i64 = -1;
    let deck_for = |c: &str, s: i64| -> Vec<CardId> {
        if let Some(l) = fixed.get(c) {
            if hero.is_empty() || hero == c {
                return l[0].clone();
            }
        }
        build_deck(c, s)
    };
    for x in &cls {
        for y in &cls {
            if !hero.is_empty() && *x != hero && *y != hero {
                continue;
            }
            for _ in 0..games {
                k += 1;
                let seed = base * 1000003 + k * 7919;
                jobs.push(Job { a: x.clone(), b: y.clone(), seed, d0: deck_for(x, seed + 1), d1: deck_for(y, seed + 2) });
            }
        }
    }
    let t0 = std::time::Instant::now();
    let n = jobs.len();
    let v = variant.clone();
    let recs = par_map(jobs, threads(a), Arc::new(move |j: &Job| play(&j.a, &j.b, &j.d0, &j.d1, j.seed, &v)));
    let secs = t0.elapsed().as_secs_f64();
    eprintln!("[lab] {} games in {:.1}s ({:.0}/s)", n, secs, n as f64 / secs);
    if a.has("out") {
        let mut s = String::new();
        for r in &recs {
            s.push_str(&r.to_json().dump());
            s.push('\n');
        }
        std::fs::write(a.get("out", ""), s).expect("write");
    }
    print!("{}", report(&recs, &cls));
}

/// Win rates per Boss (both seats), the matchup grid, and going first.
pub fn report(recs: &[Rec], cls: &[String]) -> String {
    let mut wins: HashMap<String, (f64, f64)> = HashMap::new();
    let mut mu: HashMap<(String, String), (f64, f64)> = HashMap::new();
    let (mut first, mut nfirst) = (0.0, 0.0);
    for r in recs {
        let sa = r.score_a();
        if r.a == r.b {
            first += sa;
            nfirst += 1.0;
            continue;
        }
        first += sa;
        nfirst += 1.0;
        let e = wins.entry(r.a.clone()).or_insert((0.0, 0.0));
        e.0 += sa;
        e.1 += 1.0;
        let e = wins.entry(r.b.clone()).or_insert((0.0, 0.0));
        e.0 += 1.0 - sa;
        e.1 += 1.0;
        let e = mu.entry((r.a.clone(), r.b.clone())).or_insert((0.0, 0.0));
        e.0 += sa;
        e.1 += 1.0;
        let e = mu.entry((r.b.clone(), r.a.clone())).or_insert((0.0, 0.0));
        e.0 += 1.0 - sa;
        e.1 += 1.0;
    }
    let mut out = String::new();
    let mut rows: Vec<(&String, f64, f64)> = cls.iter().filter_map(|c| wins.get(c).map(|(w, n)| (c, w / n, *n))).collect();
    rows.sort_by(|x, y| y.1.partial_cmp(&x.1).unwrap());
    out.push_str("Boss        win%    games\n");
    for (c, wr, n) in &rows {
        out.push_str(&format!("{:<10} {:5.1}%  {:6}\n", c, wr * 100.0, *n as i64));
    }
    if nfirst > 0.0 {
        out.push_str(&format!("going first {:5.1}%  ({} games)\n", first / nfirst * 100.0, nfirst as i64));
    }
    out.push_str("\nrow beats column (row's win %):\n          ");
    for c in cls {
        out.push_str(&format!("{:>9}", &c[..c.len().min(8)]));
    }
    out.push('\n');
    let mut worst = (1.0, String::new());
    for r in cls {
        out.push_str(&format!("{:<10}", r));
        for c in cls {
            match mu.get(&(r.clone(), c.clone())) {
                Some((w, n)) if *n > 0.0 => {
                    let p = w / n;
                    if p < worst.0 {
                        worst = (p, format!("{} vs {}", r, c));
                    }
                    out.push_str(&format!("{:>8.0}%", p * 100.0))
                }
                _ => out.push_str("        -"),
            }
        }
        out.push('\n');
    }
    if !worst.1.is_empty() {
        out.push_str(&format!("worst matchup: {} {:.0}/{:.0}\n", worst.1, worst.0 * 100.0, 100.0 - worst.0 * 100.0));
    }
    out
}

// --- search ---

const REFRESH: i64 = 15;
const STARTS: usize = 6;

fn field_deck(field: &HashMap<String, Vec<Vec<CardId>>>, opp: &str, i: usize, n_opp: usize, sd: i64) -> Vec<CardId> {
    match field.get(opp) {
        Some(l) if !l.is_empty() => l[(i / n_opp) % l.len()].clone(),
        _ => build_deck(opp, sd + 11),
    }
}

/// Win rate of `deck` over the games in `seeds` (opponents cycle, seats
/// alternate), spread over all cores.
fn score(cls: &str, deck: &[CardId], seeds: &[i64], field: &Arc<HashMap<String, Vec<Vec<CardId>>>>, nt: usize) -> f64 {
    let opps: Vec<String> = db().classes.iter().filter(|c| *c != cls).cloned().collect();
    let jobs: Vec<(usize, i64)> = seeds.iter().copied().enumerate().collect();
    let (cls2, deck2, field2) = (cls.to_string(), deck.to_vec(), field.clone());
    let res = par_map(
        jobs,
        nt,
        Arc::new(move |&(i, sd): &(usize, i64)| {
            let opp = &opps[i % opps.len()];
            let od = field_deck(&field2, opp, i, opps.len(), sd);
            if (i / opps.len()) % 2 == 0 {
                play(&cls2, opp, &deck2, &od, sd, "").score_a()
            } else {
                1.0 - play(opp, &cls2, &od, &deck2, sd, "").score_a()
            }
        }),
    );
    res.iter().sum::<f64>() / seeds.len() as f64
}

fn mutate(deck: &[CardId], pool: &[CardId], rng: &mut Rng) -> Vec<CardId> {
    let mut d = deck.to_vec();
    let n = [1, 1, 2, 2, 3][rng.randi_range(0, 4) as usize];
    for _ in 0..n {
        d.remove(rng.randi_range(0, d.len() as i64 - 1) as usize);
        let mut guard = 0;
        while d.len() < DECK_SIZE && guard < 500 {
            guard += 1;
            let c = pool[rng.randi_range(0, pool.len() as i64 - 1) as usize];
            if d.iter().filter(|&&x| x == c).count() < db().card(c).max_copies() {
                d.push(c);
            }
        }
    }
    d
}

pub fn search_one(cls: &str, iters: i64, games: i64, base: i64, field: Arc<HashMap<String, Vec<Vec<CardId>>>>, start: Option<Vec<CardId>>, nt: usize, verbose: bool) -> (Vec<CardId>, f64, f64) {
    let mut rng = Rng::new(base * 31 + cls.len() as i64 * 7);
    let pool = db().pool(cls);
    let seed_set = |b: i64| -> Vec<i64> { (0..games).map(|i| b + 1 + i * 7919).collect() };
    let mut seeds = seed_set(base * 100000);
    let mut starts: Vec<Vec<CardId>> = vec![];
    if let Some(s) = start {
        starts.push(s);
    }
    while starts.len() < if starts.is_empty() { STARTS } else { 2 } {
        let k = starts.len() as i64;
        starts.push(build_deck(cls, base * 977 + k));
    }
    let (mut champ, mut cs) = (vec![], -1.0);
    for d in starts {
        let s = score(cls, &d, &seeds, &field, nt);
        if s > cs {
            champ = d;
            cs = s;
        }
    }
    for it in 1..=iters {
        if it % REFRESH == 0 {
            seeds = seed_set(base * 100000 + it * 1000);
            cs = score(cls, &champ, &seeds, &field, nt);
        }
        let cand = mutate(&champ, &pool, &mut rng);
        let s = score(cls, &cand, &seeds, &field, nt);
        if s > cs {
            champ = cand;
            cs = s;
        }
        if verbose && it % 10 == 0 {
            eprintln!("[search {}] {} / {}  {:.3}", cls, it, iters, cs);
        }
    }
    let fin: Vec<i64> = (0..games * 3).map(|i| base * 7777777 + 1 + i * 104729).collect();
    let fwr = score(cls, &champ, &fin, &field, nt);
    let rwr = score(cls, &build_deck(cls, base * 31337), &fin, &field, nt);
    (champ, fwr, rwr)
}

fn deck_json(d: &[CardId]) -> J {
    let mut v: Vec<String> = d.iter().map(|&c| db().card(c).id.clone()).collect();
    v.sort();
    J::Arr(v.into_iter().map(J::Str).collect())
}

fn search(a: &Args) {
    let cls = a.get("class", "");
    if cls.is_empty() {
        eprintln!("--class is required");
        return;
    }
    let field = Arc::new(if a.has("field") { load_lists(&a.get("field", "")) } else { HashMap::new() });
    let start = if a.has("start") { load_lists(&a.get("start", "")).get(&cls).map(|l| l[0].clone()) } else { None };
    let t0 = std::time::Instant::now();
    let (deck, fwr, rwr) = search_one(&cls, a.int("iters", 100), a.int("games", 160), a.int("seed", 7), field, start, threads(a), true);
    eprintln!("[lab] search {} done in {:.0}s", cls, t0.elapsed().as_secs_f64());
    println!("{}: tuned list {:.1}% vs a random list {:.1}% (fresh games)", cls, fwr * 100.0, rwr * 100.0);
    print_deck(&deck);
    if a.has("out") {
        let j = obj(vec![("class", st(&cls)), ("deck", deck_json(&deck)), ("final_wr", J::Num(fwr)), ("random_deck_wr", J::Num(rwr))]);
        std::fs::write(a.get("out", ""), j.dump()).expect("write");
    }
}

fn print_deck(deck: &[CardId]) {
    let d = db();
    let mut counts: Vec<(CardId, usize)> = vec![];
    for &c in deck {
        match counts.iter_mut().find(|x| x.0 == c) {
            Some(x) => x.1 += 1,
            None => counts.push((c, 1)),
        }
    }
    counts.sort_by_key(|x| (d.card(x.0).cost, d.card(x.0).name.clone()));
    for (c, n) in counts {
        let card = d.card(c);
        println!("  {}x {:>2}  {}", n, card.cost, card.name);
    }
}

// --- pick ---

fn pick(a: &Args) {
    let pool = load_lists(&a.get("pool", ""));
    let games = a.int("games", 300);
    let nt = threads(a);
    let cls = db().classes.clone();
    let t0 = std::time::Instant::now();
    // Round 1: every list vs every other Boss's lists. Round 2: vs the top 3.
    let round = |field: &HashMap<String, Vec<Vec<CardId>>>, g: i64, seed: i64| -> HashMap<String, Vec<f64>> {
        let f = Arc::new(field.clone());
        let mut out = HashMap::new();
        for c in &cls {
            let seeds: Vec<i64> = (0..g).map(|i| seed * 1000003 + i * 7919 + c.len() as i64).collect();
            let sc: Vec<f64> = pool.get(c).map(|l| l.iter().map(|d| score(c, d, &seeds, &f, nt)).collect()).unwrap_or_default();
            out.insert(c.clone(), sc);
        }
        out
    };
    let r1 = round(&pool, (games * 4 / 5).max(60), 5);
    let mut field2 = HashMap::new();
    for c in &cls {
        let s = &r1[c];
        let mut idx: Vec<usize> = (0..s.len()).collect();
        idx.sort_by(|&x, &y| s[y].partial_cmp(&s[x]).unwrap());
        field2.insert(c.clone(), idx.iter().take(3).map(|&i| pool[c][i].clone()).collect::<Vec<_>>());
    }
    // Round 2: every list against the top 3 of each other Boss.
    let r2 = round(&field2, games, 9);
    let mut best = HashMap::new();
    for c in &cls {
        let sc = &r2[c];
        let bi = (0..sc.len()).max_by(|&x, &y| sc[x].partial_cmp(&sc[y]).unwrap()).unwrap();
        eprintln!("[pick {}] best list {:.1}% (of {})", c, sc[bi] * 100.0, sc.len());
        best.insert(c.clone(), pool[c][bi].clone());
    }
    // The meta with each Boss on its best list.
    let mut jobs = vec![];
    let mut k: i64 = -1;
    for x in &cls {
        for y in &cls {
            for _ in 0..games {
                k += 1;
                let seed = 97 * 1000003 + k * 7919;
                jobs.push(Job { a: x.clone(), b: y.clone(), seed, d0: best[x].clone(), d1: best[y].clone() });
            }
        }
    }
    let recs = par_map(jobs, nt, Arc::new(|j: &Job| play(&j.a, &j.b, &j.d0, &j.d1, j.seed, "")));
    eprintln!("[lab] pick done in {:.0}s", t0.elapsed().as_secs_f64());
    print!("{}", report(&recs, &cls));
    if a.has("out") {
        let dir = a.get("out", "");
        std::fs::create_dir_all(&dir).ok();
        let bj = J::Obj(best.iter().map(|(k, v)| (k.clone(), deck_json(v))).collect());
        std::fs::write(format!("{}/best.json", dir), bj.dump()).ok();
        std::fs::write(format!("{}/report.txt", dir), report(&recs, &cls)).ok();
    }
}

// --- cards ---

pub fn card_line(c: &Card) -> String {
    let stats = if c.kind == Kind::Minion { format!("{}/{}", c.attack, c.health) } else { "Trick".into() };
    let text = if c.text.is_empty() { String::new() } else { format!("  {}", c.text) };
    format!("{} ({}) {}{}", c.name, c.cost, stats, text)
}

fn cards(a: &Args) {
    let d = db();
    let cls = a.get("class", "");
    let find = a.get("find", "").to_lowercase();
    for i in 0..d.n_real {
        let c = &d.cards[i];
        if !cls.is_empty() && c.class != cls {
            continue;
        }
        if !find.is_empty() && !format!("{} {}", c.name, c.text).to_lowercase().contains(&find) {
            continue;
        }
        println!("{:<26} {}", c.id, card_line(c));
    }
}

fn bench(a: &Args) {
    let n = a.int("games", 400);
    let t0 = std::time::Instant::now();
    let jobs: Vec<i64> = (0..n).collect();
    let cls = db().classes.clone();
    let r = par_map(
        jobs,
        threads(a),
        Arc::new(move |&k: &i64| {
            let (x, y) = (&cls[(k % 6) as usize], &cls[((k / 6) % 6) as usize]);
            play(x, y, &build_deck(x, k * 3 + 1), &build_deck(y, k * 3 + 2), k * 7919, "").t
        }),
    );
    let s = t0.elapsed().as_secs_f64();
    println!("{} games in {:.2}s = {:.0} games/s (avg {} turns)", n, s, n as f64 / s, r.iter().sum::<i32>() / n as i32);
}

// --- play by text ---

fn play_cmd(a: &Args) {
    let sub = a.pos.first().cloned().unwrap_or_else(|| "show".into());
    let save = a.get("save", "lab_game.json");
    let mut st_j: J = if sub == "new" {
        let me = a.get("me", "grunk");
        let vs = a.get("vs", "barnacle");
        let seed = a.int("seed", (std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() % 1_000_000) as i64);
        let mydeck = if a.has("deck") { load_lists(&a.get("deck", ""))[&me][0].clone() } else { build_deck(&me, seed + 1) };
        let foedeck = if a.has("foe-deck") { load_lists(&a.get("foe-deck", ""))[&vs][0].clone() } else { build_deck(&vs, seed + 2) };
        let seat: i64 = if a.has("second") { 1 } else { 0 };
        let (d0, d1, c0, c1) = if seat == 0 { (mydeck, foedeck, me.clone(), vs.clone()) } else { (foedeck, mydeck, vs.clone(), me.clone()) };
        obj(vec![
            ("seed", num(seed)),
            ("seat", num(seat)),
            ("c0", st(&c0)),
            ("c1", st(&c1)),
            ("d0", deck_json_order(&d0)),
            ("d1", deck_json_order(&d1)),
            ("moves", J::Arr(vec![])),
            ("shown", num(0)),
        ])
    } else {
        J::parse(&std::fs::read_to_string(&save).expect("no saved game: run `lab play new` first")).expect("bad save")
    };
    let mut moves: Vec<i64> = st_j.get("moves").arr().iter().map(|x| x.i()).collect();
    match sub.as_str() {
        "move" => moves.push(a.pos.get(1).and_then(|s| s.parse().ok()).expect("move needs a number")),
        "end" => moves.push(0),
        _ => {}
    }
    let (gs, legal, err) = replay(&st_j, &moves);
    if err {
        moves.pop();
        println!("That move isn't available. Pick a number from the list.");
    }
    let shown = st_j.get("shown").i() as usize;
    let log = gs.log.clone().unwrap_or_default();
    for l in log.iter().skip(shown) {
        println!("{}", l);
    }
    if let J::Obj(m) = &mut st_j {
        m.insert("moves".into(), J::Arr(moves.iter().map(|&x| num(x)).collect()));
        m.insert("shown".into(), num(log.len() as i64));
    }
    std::fs::write(&save, st_j.dump()).expect("save");
    println!("{}", render(&gs, st_j.get("seat").i() as usize, &legal));
}

fn deck_json_order(d: &[CardId]) -> J {
    J::Arr(d.iter().map(|&c| st(&db().card(c).id)).collect())
}

/// Rebuild the game from its seed and the human's moves (0 = end turn,
/// n = the n-th move in the list shown). The bot plays its turns the same
/// way every time (its look-ahead dice are seeded from the game seed).
fn replay(s: &J, moves: &[i64]) -> (Game, Vec<Act>, bool) {
    let seed = s.get("seed").i();
    let seat = s.get("seat").i() as usize;
    let d0 = deck_ids(s.get("d0"));
    let d1 = deck_ids(s.get("d1"));
    crate::game::seed_clone_rng(seed);
    let mut gs = Game::new(seed, &d0, &d1, &s.get("c0").s(), &s.get("c1").s());
    gs.log = Some(vec![]);
    let mut bot = Ai::new(seed + 3);
    let mut mi = 0;
    let mut bad = false;
    loop {
        if gs.winner != -1 {
            return (gs, vec![], bad);
        }
        if gs.active != seat {
            let mut n = 0;
            while gs.winner == -1 && n < 60 {
                n += 1;
                let act = bot.next_action(&gs, gs.active);
                if act == Act::End {
                    break;
                }
                let p = gs.active;
                if !apply(&mut gs, p, act) {
                    break;
                }
            }
            if gs.winner == -1 {
                gs.end_turn();
            }
            continue;
        }
        let legal = legal_actions(&gs, seat);
        if mi >= moves.len() {
            return (gs, legal, bad);
        }
        let m = moves[mi];
        mi += 1;
        if m == 0 {
            if let Some(l) = &mut gs.log {
                l.push(format!("P{} ends the turn.", seat + 1));
            }
            gs.end_turn();
        } else if m >= 1 && (m as usize) <= legal.len() {
            apply(&mut gs, seat, legal[m as usize - 1]);
        } else {
            bad = true;
            return (gs, legal, bad);
        }
    }
}

fn tname(gs: &Game, t: T, me: usize) -> String {
    match t {
        T::None => String::new(),
        T::Hero(p) => if p == me { "your Boss".into() } else { "the enemy Boss".into() },
        T::Minion(p, i) => {
            let m = &gs.players[p].board[i as usize];
            format!("{}{} {}", if p == me { "your " } else { "enemy " }, if p == me { format!("m{}", i + 1) } else { format!("e{}", i + 1) }, m.name())
        }
    }
}

fn minion_line(m: &Minion) -> String {
    let mut tags = vec![];
    if m.taunt {
        tags.push("Bouncer");
    }
    if m.has(KW_SHIELD) {
        tags.push("Stunt Double");
    }
    if m.has(KW_STEALTH) {
        tags.push("Backstage");
    }
    if m.has(KW_WINDFURY) {
        tags.push("Encore");
    }
    if m.has(KW_POISON) {
        tags.push("Showstopper");
    }
    if m.has(KW_LIFESTEAL) {
        tags.push("Tip Jar");
    }
    if m.frozen > 0 {
        tags.push("frozen");
    }
    if m.silenced {
        tags.push("Heckled");
    }
    let c = db().card(m.card);
    let text = if m.silenced || c.text.is_empty() { String::new() } else { format!(" | {}", c.text) };
    format!("{} {}/{}{}{}", m.name(), m.attack, m.health, if tags.is_empty() { String::new() } else { format!(" [{}]", tags.join(", ")) }, text)
}

pub fn render(gs: &Game, me: usize, legal: &[Act]) -> String {
    let d = db();
    let foe = 1 - me;
    let (p, q) = (&gs.players[me], &gs.players[foe]);
    let mut o = String::new();
    o.push_str(&format!("\n=== Turn {} ===\n", gs.turn_count));
    o.push_str(&format!("ENEMY {}: {} Health, {}/{} mana, {} cards in hand, {} in deck\n", q.class, q.hp, q.mana, q.max_mana, q.hand.len(), q.deck.len()));
    for (i, m) in q.board.iter().enumerate() {
        o.push_str(&format!("  e{}  {}\n", i + 1, minion_line(m)));
    }
    o.push_str("  ------------------------------\n");
    for (i, m) in p.board.iter().enumerate() {
        let ready = if gs.can_attack(me, i) && gs.active == me { " (ready)" } else { "" };
        o.push_str(&format!("  m{}  {}{}\n", i + 1, minion_line(m), ready));
    }
    let owed = if p.overload_next > 0 { format!(", {} owed next turn", p.overload_next) } else { String::new() };
    o.push_str(&format!("YOU {}: {} Health, {}/{} mana{}, {} in deck\n", p.class, p.hp, p.mana, p.max_mana, owed, p.deck.len()));
    o.push_str("Hand:\n");
    for (i, &c) in p.hand.iter().enumerate() {
        o.push_str(&format!("  h{}  {}\n", i + 1, card_line(d.card(c))));
    }
    if let Some(hp) = gs.hero_power(me) {
        o.push_str(&format!("Signature Move (2): {} - {}{}\n", hp.name, hp.text, if p.hero_power_used { " (used)" } else { "" }));
    }
    if gs.winner != -1 {
        o.push_str(&format!("\nGAME OVER: {}\n", if gs.winner == me as i32 { "you win" } else { "you lose" }));
        return o;
    }
    o.push_str("\nMoves:  0) end turn\n");
    for (i, a) in legal.iter().enumerate() {
        let s = match *a {
            Act::Play(hi, t) => {
                let c = d.card(p.hand[hi]);
                if t == T::None { format!("play h{} {}", hi + 1, c.name) } else { format!("play h{} {} at {}", hi + 1, c.name, tname(gs, t, me)) }
            }
            Act::Power(t) => {
                if t == T::None { "Signature Move".to_string() } else { format!("Signature Move on {}", tname(gs, t, me)) }
            }
            Act::Attack(b, t) => format!("m{} {} attacks {}", b + 1, p.board[b].name(), tname(gs, t, me)),
            Act::End => String::new(),
        };
        o.push_str(&format!("  {:>2}) {}\n", i + 1, s));
    }
    o
}
