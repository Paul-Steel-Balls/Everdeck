//! Godot 4's RandomNumberGenerator (RandomPCG over PCG32), copied exactly
//! so the Lab rolls the same dice as the game for the same seed.

const DEFAULT_INC: u64 = 1442695040888963407;

#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
    inc: u64,
}

impl Rng {
    pub fn new(seed: i64) -> Rng {
        let mut r = Rng { state: 0, inc: 0 };
        r.seed(seed);
        r
    }

    /// Godot: rng.seed = s (pcg32_srandom_r with the default stream).
    pub fn seed(&mut self, s: i64) {
        let initstate = s as u64;
        self.state = 0;
        self.inc = (DEFAULT_INC << 1) | 1;
        self.next_u32();
        self.state = self.state.wrapping_add(initstate);
        self.next_u32();
    }

    /// A seed from the clock (Godot: randomize()).
    pub fn randomize(&mut self) {
        use std::time::{SystemTime, UNIX_EPOCH};
        let t = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1);
        self.seed((t ^ (t >> 17).wrapping_mul(0x9E3779B97F4A7C15)) as i64);
    }

    #[inline]
    pub fn next_u32(&mut self) -> u32 {
        let old = self.state;
        self.state = old.wrapping_mul(6364136223846793005).wrapping_add(self.inc);
        let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
        let rot = (old >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    #[inline]
    fn bounded(&mut self, bound: u32) -> u32 {
        let threshold = bound.wrapping_neg() % bound;
        loop {
            let r = self.next_u32();
            if r >= threshold {
                return r % bound;
            }
        }
    }

    /// Godot: randi_range(from, to), both ends included.
    pub fn randi_range(&mut self, from: i64, to: i64) -> i64 {
        if from == to {
            return from;
        }
        let span = (from - to).unsigned_abs() as u32 + 1;
        self.bounded(span) as i64 + from.min(to)
    }

    /// Godot: randi().
    pub fn randi(&mut self) -> i64 {
        self.next_u32() as i64
    }

    /// Godot: randf() (a 32-bit float, widened like GDScript does).
    pub fn randf(&mut self) -> f64 {
        let proto = self.next_u32();
        if proto == 0 {
            return 0.0;
        }
        let v = (self.next_u32() | 0x8000_0001) as f32;
        let e = -32 - proto.leading_zeros() as i32;
        (v * 2f32.powi(e)) as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matches_godot() {
        // From tools/lab_rng_dump.gd (Godot 4.7.2).
        let want: Vec<(i64, Vec<i64>, i64, [&str; 3], i64)> = vec![
            (0, vec![1, 0, 0, 3, 3, 6, 3], 2901098513, ["00000000427feb3f", "000000e01a36de3f", "00000000e3ade63f"], 0),
            (1, vec![1, 0, 1, 3, 3, 0, 3], 1039475129, ["000000e08bc3e03f", "000000c0d64ba83f", "00000040068ae53f"], -1),
            (12345, vec![0, 1, 1, 0, 0, 0, 3], 1040420088, ["000000a0c3f1eb3f", "000000607144ef3f", "000000e0146fe43f"], -1),
            (5007934, vec![1, 1, 3, 4, 0, 3, 5], 49685124, ["00000080bb4bda3f", "000000603835c03f", "00000020f71aef3f"], 3),
            (-7, vec![1, 2, 1, 3, 1, 0, 3], 415254630, ["000000a09db3d23f", "000000e0a13be23f", "000000e0bf6fc93f"], -2),
            (9007199254740993, vec![1, 0, 0, 3, 1, 3, 3], 2281554479, ["000000e09d43d53f", "000000a05fa8c13f", "000000009fa1e13f"], 3),
        ];
        for (s, ranges, ri, fl, last) in want {
            let mut r = Rng::new(s);
            let mut got = vec![];
            for i in 0..6 {
                got.push(r.randi_range(0, i + 1));
            }
            got.push(r.randi_range(2, 5));
            assert_eq!(got, ranges, "seed {s}");
            assert_eq!(r.randi(), ri, "seed {s}");
            for f in fl {
                let b = r.randf().to_le_bytes();
                let hex: String = b.iter().map(|x| format!("{:02x}", x)).collect();
                assert_eq!(hex, f, "seed {s}");
            }
            assert_eq!(r.randi_range(-3, 3), last, "seed {s}");
            assert_eq!(r.randi_range(5, 5), 5);
        }
    }
}
