//! A small JSON reader/writer (the Lab builds with no outside packages).

use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq)]
pub enum J {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<J>),
    Obj(BTreeMap<String, J>),
}

impl J {
    pub fn get(&self, k: &str) -> &J {
        static NULL: J = J::Null;
        match self {
            J::Obj(m) => m.get(k).unwrap_or(&NULL),
            _ => &NULL,
        }
    }
    pub fn has(&self, k: &str) -> bool {
        matches!(self, J::Obj(m) if m.contains_key(k))
    }
    pub fn s(&self) -> String {
        match self {
            J::Str(s) => s.clone(),
            J::Num(n) => format!("{}", n),
            J::Bool(b) => format!("{}", b),
            _ => String::new(),
        }
    }
    pub fn i(&self) -> i64 {
        match self {
            J::Num(n) => *n as i64,
            J::Str(s) => s.parse().unwrap_or(0),
            J::Bool(b) => *b as i64,
            _ => 0,
        }
    }
    pub fn f(&self) -> f64 {
        match self {
            J::Num(n) => *n,
            _ => 0.0,
        }
    }
    pub fn arr(&self) -> &[J] {
        match self {
            J::Arr(a) => a,
            _ => &[],
        }
    }
    pub fn obj(&self) -> Option<&BTreeMap<String, J>> {
        match self {
            J::Obj(m) => Some(m),
            _ => None,
        }
    }
    pub fn is_null(&self) -> bool {
        matches!(self, J::Null)
    }

    pub fn parse(src: &str) -> Result<J, String> {
        let b = src.as_bytes();
        let mut p = 0usize;
        let v = parse_val(b, &mut p)?;
        skip_ws(b, &mut p);
        Ok(v)
    }

    pub fn dump(&self) -> String {
        let mut o = String::new();
        dump_into(self, &mut o);
        o
    }
}

fn skip_ws(b: &[u8], p: &mut usize) {
    while *p < b.len() && (b[*p] as char).is_ascii_whitespace() {
        *p += 1;
    }
}

fn parse_val(b: &[u8], p: &mut usize) -> Result<J, String> {
    skip_ws(b, p);
    if *p >= b.len() {
        return Err("unexpected end".into());
    }
    match b[*p] {
        b'{' => {
            *p += 1;
            let mut m = BTreeMap::new();
            loop {
                skip_ws(b, p);
                if b[*p] == b'}' {
                    *p += 1;
                    break;
                }
                let k = match parse_val(b, p)? {
                    J::Str(s) => s,
                    _ => return Err(format!("object key at {}", p)),
                };
                skip_ws(b, p);
                if b[*p] != b':' {
                    return Err(format!("expected : at {}", p));
                }
                *p += 1;
                let v = parse_val(b, p)?;
                m.insert(k, v);
                skip_ws(b, p);
                if b[*p] == b',' {
                    *p += 1;
                }
            }
            Ok(J::Obj(m))
        }
        b'[' => {
            *p += 1;
            let mut a = vec![];
            loop {
                skip_ws(b, p);
                if b[*p] == b']' {
                    *p += 1;
                    break;
                }
                a.push(parse_val(b, p)?);
                skip_ws(b, p);
                if b[*p] == b',' {
                    *p += 1;
                }
            }
            Ok(J::Arr(a))
        }
        b'"' => {
            *p += 1;
            let mut s = String::new();
            while b[*p] != b'"' {
                if b[*p] == b'\\' {
                    *p += 1;
                    match b[*p] {
                        b'n' => s.push('\n'),
                        b't' => s.push('\t'),
                        b'r' => s.push('\r'),
                        b'b' => s.push('\u{8}'),
                        b'f' => s.push('\u{c}'),
                        b'u' => {
                            let h = std::str::from_utf8(&b[*p + 1..*p + 5]).map_err(|e| e.to_string())?;
                            let mut cp = u32::from_str_radix(h, 16).map_err(|e| e.to_string())?;
                            *p += 4;
                            if (0xD800..0xDC00).contains(&cp) && b.get(*p + 1) == Some(&b'\\') {
                                let h2 = std::str::from_utf8(&b[*p + 3..*p + 7]).map_err(|e| e.to_string())?;
                                let lo = u32::from_str_radix(h2, 16).map_err(|e| e.to_string())?;
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                *p += 6;
                            }
                            s.push(char::from_u32(cp).unwrap_or('?'));
                        }
                        c => s.push(c as char),
                    }
                    *p += 1;
                } else {
                    let start = *p;
                    while b[*p] != b'"' && b[*p] != b'\\' {
                        *p += 1;
                    }
                    s.push_str(std::str::from_utf8(&b[start..*p]).map_err(|e| e.to_string())?);
                }
            }
            *p += 1;
            Ok(J::Str(s))
        }
        b't' => {
            *p += 4;
            Ok(J::Bool(true))
        }
        b'f' => {
            *p += 5;
            Ok(J::Bool(false))
        }
        b'n' => {
            *p += 4;
            Ok(J::Null)
        }
        _ => {
            let start = *p;
            while *p < b.len() && matches!(b[*p], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') {
                *p += 1;
            }
            let t = std::str::from_utf8(&b[start..*p]).unwrap();
            t.parse::<f64>().map(J::Num).map_err(|_| format!("bad number '{}' at {}", t, start))
        }
    }
}

fn dump_str(s: &str, o: &mut String) {
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
}

fn dump_into(v: &J, o: &mut String) {
    match v {
        J::Null => o.push_str("null"),
        J::Bool(b) => o.push_str(if *b { "true" } else { "false" }),
        J::Num(n) => {
            if n.fract() == 0.0 && n.abs() < 1e15 {
                o.push_str(&format!("{}", *n as i64))
            } else {
                o.push_str(&format!("{}", n))
            }
        }
        J::Str(s) => dump_str(s, o),
        J::Arr(a) => {
            o.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    o.push(',');
                }
                dump_into(x, o);
            }
            o.push(']');
        }
        J::Obj(m) => {
            o.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    o.push(',');
                }
                dump_str(k, o);
                o.push(':');
                dump_into(x, o);
            }
            o.push('}');
        }
    }
}

/// Build helpers.
pub fn num(n: i64) -> J {
    J::Num(n as f64)
}
pub fn st(s: &str) -> J {
    J::Str(s.to_string())
}
pub fn obj(pairs: Vec<(&str, J)>) -> J {
    J::Obj(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}
