//! The exchange: a pretend 1980s-style stock market that runs while you play.
//! Companies, sectors and news reactions are data (`data/market.ron`).
//!
//! Model: every company has a fundamental `value`. News moves the value at
//! once (a step); the traded `price` chases the value with lag, momentum and
//! noise, so a shock shows up as a sharp move that keeps running for a while.
//! Sectors add correlated drift, so steel names move together.
//!
//! Built to be extended. Anything that happens in the game is reported as a
//! string key, e.g. `death:gov_saptavarta`, `method:poison`, `alarm`,
//! `removed:gov_vatsabhumi`, `night`. Two things respond to a key:
//! 1. `reactions` in data, matched by exact key or by a `prefix:*` wildcard;
//! 2. company `ties` to entities. For a `death:<id>` or `removed:<id>` key,
//!    every company tied to `<id>` moves by its tie sensitivity.
//! So when characters arrive later, giving them ids and tying companies to
//! them in data is enough. No code changes are needed.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::rng::Rng;
use crate::LoadError;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SectorDef {
    pub id: String,
    pub name: String,
    /// Drift per market tick (fraction, e.g. 0.0002).
    #[serde(default)]
    pub drift: f32,
    /// Shared noise per tick (fraction).
    pub volatility: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Tie {
    /// Any entity id: governor, character, faction.
    pub entity: String,
    /// Fractional value change when the entity dies or is removed
    /// (negative: the company loses a patron).
    pub on_death: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CompanyDef {
    pub id: String,
    pub name: String,
    pub ticker: String,
    pub sector: String,
    pub price: f32,
    /// Idiosyncratic noise per tick (fraction).
    pub volatility: f32,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub ties: Vec<Tie>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MoveDef {
    /// Company id, `sector:<id>`, or `all`.
    pub target: String,
    /// Fractional change in fundamental value (0.08 = +8%).
    pub pct: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReactionDef {
    /// Exact event key, or `prefix:*`.
    pub key: String,
    /// Headline for the tape; `{scale}` is not substituted, keep it plain.
    #[serde(default)]
    pub headline: String,
    pub moves: Vec<MoveDef>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MarketDef {
    pub exchange: String,
    pub currency: String,
    pub start_cash: f32,
    /// Real seconds per market tick while playing.
    pub tick_seconds: f32,
    /// Ticks simulated when a night passes in the war room.
    pub night_ticks: u32,
    pub sectors: Vec<SectorDef>,
    pub companies: Vec<CompanyDef>,
    #[serde(default)]
    pub reactions: Vec<ReactionDef>,
}

impl MarketDef {
    pub fn load(path: &std::path::Path) -> Result<Self, LoadError> {
        let d: MarketDef = crate::read_ron(path)?;
        d.validate()?;
        Ok(d)
    }

    pub fn validate(&self) -> Result<(), LoadError> {
        for c in &self.companies {
            if !self.sectors.iter().any(|s| s.id == c.sector) {
                return Err(LoadError(format!("market: company {} has unknown sector {}", c.id, c.sector)));
            }
        }
        for r in &self.reactions {
            for m in &r.moves {
                let ok = m.target == "all"
                    || m.target.strip_prefix("sector:").map(|s| self.sectors.iter().any(|x| x.id == s)).unwrap_or(false)
                    || self.companies.iter().any(|c| c.id == m.target);
                if !ok {
                    return Err(LoadError(format!("market: reaction {} targets unknown {}", r.key, m.target)));
                }
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Quote {
    pub id: String,
    pub price: f32,
    pub value: f32,
    /// Price at the start of the session (for the day's change).
    pub open: f32,
    pub momentum: f32,
    pub history: Vec<f32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct News {
    pub tick: u64,
    pub text: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Market {
    pub quotes: Vec<Quote>,
    pub cash: f32,
    pub holdings: BTreeMap<String, i64>,
    /// Average cost per share, for unrealised profit.
    pub cost: BTreeMap<String, f32>,
    pub news: Vec<News>,
    pub tick: u64,
    rng: Rng,
    #[serde(default)]
    acc: f32,
}

pub const HISTORY: usize = 90;

fn gauss(r: &mut Rng) -> f32 {
    // Box-Muller.
    let u1 = r.next_f32().max(1e-6);
    let u2 = r.next_f32();
    (-2.0 * u1.ln()).sqrt() * (std::f32::consts::TAU * u2).cos()
}

impl Market {
    pub fn new(d: &MarketDef, seed: u64) -> Self {
        let mut m = Self {
            quotes: d
                .companies
                .iter()
                .map(|c| Quote { id: c.id.clone(), price: c.price, value: c.price, open: c.price, momentum: 0.0, history: vec![c.price] })
                .collect(),
            cash: d.start_cash,
            holdings: BTreeMap::new(),
            cost: BTreeMap::new(),
            news: vec![],
            tick: 0,
            rng: Rng::new(seed ^ 0x5106_7A11),
            acc: 0.0,
        };
        // Warm up so the charts have shape on the first look.
        for _ in 0..HISTORY {
            m.step(d);
        }
        for q in &mut m.quotes {
            q.open = q.price;
        }
        m
    }

    /// A save from before a company was listed: quotes line up with companies
    /// again, new listings start at their list price.
    pub fn refresh_listings(&mut self, d: &MarketDef) {
        let mut quotes = Vec::with_capacity(d.companies.len());
        for c in &d.companies {
            match self.quotes.iter().find(|q| q.id == c.id) {
                Some(q) => quotes.push(q.clone()),
                None => quotes.push(Quote { id: c.id.clone(), price: c.price, value: c.price, open: c.price, momentum: 0.0, history: vec![c.price] }),
            }
        }
        self.quotes = quotes;
    }

    /// Advance by real time while playing.
    pub fn advance(&mut self, d: &MarketDef, dt: f32) -> bool {
        self.acc += dt;
        let mut ticked = false;
        while self.acc >= d.tick_seconds {
            self.acc -= d.tick_seconds;
            self.step(d);
            ticked = true;
        }
        ticked
    }

    /// One market tick.
    pub fn step(&mut self, d: &MarketDef) {
        self.tick += 1;
        let sector_noise: Vec<(String, f32)> = d
            .sectors
            .iter()
            .map(|s| (s.id.clone(), s.drift + s.volatility * gauss(&mut self.rng)))
            .collect();
        for (i, c) in d.companies.iter().enumerate() {
            let sec = sector_noise.iter().find(|(id, _)| *id == c.sector).map(|x| x.1).unwrap_or(0.0);
            let q = &mut self.quotes[i];
            // Fundamental random walk (small) plus sector co-movement.
            q.value *= 1.0 + sec * 0.5 + c.volatility * 0.25 * gauss(&mut self.rng);
            // Price chases value with lag and momentum, plus trading noise.
            let gap = (q.value - q.price) / q.price.max(0.01);
            q.momentum = q.momentum * 0.8 + gap * 0.08;
            let noise = c.volatility * gauss(&mut self.rng) + sec * 0.5;
            q.price = (q.price * (1.0 + q.momentum + noise)).max(0.125);
            q.history.push(q.price);
            if q.history.len() > HISTORY {
                q.history.remove(0);
            }
        }
    }

    fn apply_move(&mut self, d: &MarketDef, target: &str, pct: f32) {
        for (i, c) in d.companies.iter().enumerate() {
            let hit = target == "all"
                || target == c.id
                || target.strip_prefix("sector:").map(|s| s == c.sector).unwrap_or(false);
            if hit {
                let q = &mut self.quotes[i];
                q.value = (q.value * (1.0 + pct)).max(0.25);
                // Part of the move gaps through at once, the rest drifts in.
                q.price = (q.price * (1.0 + pct * 0.35)).max(0.125);
            }
        }
    }

    /// Report something that happened. Returns headlines for the tape.
    pub fn event(&mut self, d: &MarketDef, key: &str, scale: f32) -> Vec<String> {
        let mut out = vec![];
        for r in &d.reactions {
            let matched = if let Some(prefix) = r.key.strip_suffix('*') {
                key.starts_with(prefix)
            } else {
                r.key == key
            };
            if matched {
                for m in &r.moves {
                    self.apply_move(d, &m.target, m.pct * scale);
                }
                if !r.headline.is_empty() {
                    out.push(r.headline.clone());
                }
            }
        }
        // Entity ties: death:<id> / removed:<id>.
        let entity = key.strip_prefix("death:").or_else(|| key.strip_prefix("removed:"));
        if let Some(e) = entity {
            let mut tied = vec![];
            for c in &d.companies {
                for t in &c.ties {
                    if t.entity == e {
                        tied.push((c.id.clone(), t.on_death, c.ticker.clone()));
                    }
                }
            }
            for (id, pct, ticker) in tied {
                self.apply_move(d, &id, pct * scale);
                let dir = if pct < 0.0 { "slides" } else { "jumps" };
                out.push(format!("{ticker} {dir} on news of {e}"));
            }
        }
        for h in &out {
            self.news.push(News { tick: self.tick, text: h.clone() });
        }
        if self.news.len() > 40 {
            let n = self.news.len() - 40;
            self.news.drain(0..n);
        }
        out
    }

    fn idx(&self, id: &str) -> Option<usize> {
        self.quotes.iter().position(|q| q.id == id)
    }

    pub fn price(&self, id: &str) -> Option<f32> {
        self.idx(id).map(|i| self.quotes[i].price)
    }

    /// Buy (qty > 0) or sell (qty < 0) at the current price, no fees.
    pub fn trade(&mut self, id: &str, qty: i64) -> Result<(), String> {
        let Some(i) = self.idx(id) else { return Err(format!("no such listing: {id}")) };
        let p = self.quotes[i].price;
        let held = *self.holdings.get(id).unwrap_or(&0);
        if qty > 0 {
            let cost = p * qty as f32;
            if cost > self.cash + 1e-3 {
                return Err("Insufficient funds.".into());
            }
            self.cash -= cost;
            let avg = *self.cost.get(id).unwrap_or(&0.0);
            let new_held = held + qty;
            self.cost.insert(id.into(), (avg * held as f32 + cost) / new_held as f32);
            self.holdings.insert(id.into(), new_held);
        } else if qty < 0 {
            let n = -qty;
            if n > held {
                return Err("You do not hold that many shares.".into());
            }
            self.cash += p * n as f32;
            if held - n == 0 {
                self.holdings.remove(id);
                self.cost.remove(id);
            } else {
                self.holdings.insert(id.into(), held - n);
            }
        }
        Ok(())
    }

    pub fn portfolio_value(&self) -> f32 {
        self.holdings.iter().map(|(id, n)| self.price(id).unwrap_or(0.0) * *n as f32).sum()
    }

    /// Start a new trading session (the day's change resets).
    pub fn open_session(&mut self) {
        for q in &mut self.quotes {
            q.open = q.price;
        }
    }
}

/// Format a price the 1980s way, in eighths: 42.375 -> "42 3/8".
pub fn eighths(p: f32) -> String {
    let total = (p * 8.0).round() as i64;
    let whole = total / 8;
    let frac = total % 8;
    let f = match frac {
        0 => "",
        1 => " 1/8",
        2 => " 1/4",
        3 => " 3/8",
        4 => " 1/2",
        5 => " 5/8",
        6 => " 3/4",
        _ => " 7/8",
    };
    format!("{whole}{f}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn def() -> MarketDef {
        MarketDef {
            exchange: "X".into(),
            currency: "P".into(),
            start_cash: 1000.0,
            tick_seconds: 1.0,
            night_ticks: 10,
            sectors: vec![SectorDef { id: "steel".into(), name: "Steel".into(), drift: 0.0, volatility: 0.002 }],
            companies: vec![
                CompanyDef { id: "a".into(), name: "A Steel".into(), ticker: "AST".into(), sector: "steel".into(), price: 40.0, volatility: 0.004, description: String::new(),
                    ties: vec![Tie { entity: "gov_x".into(), on_death: -0.2 }] },
                CompanyDef { id: "b".into(), name: "B Steel".into(), ticker: "BST".into(), sector: "steel".into(), price: 20.0, volatility: 0.004, description: String::new(), ties: vec![] },
            ],
            reactions: vec![ReactionDef { key: "method:*".into(), headline: "Unrest".into(), moves: vec![MoveDef { target: "b".into(), pct: 0.1 }] }],
        }
    }

    #[test]
    fn deterministic_and_positive() {
        let d = def();
        let mut a = Market::new(&d, 3);
        let mut b = Market::new(&d, 3);
        for _ in 0..500 {
            a.step(&d);
            b.step(&d);
        }
        assert_eq!(a.quotes[0].price, b.quotes[0].price);
        assert!(a.quotes.iter().all(|q| q.price > 0.0 && q.history.len() <= HISTORY));
    }

    #[test]
    fn death_moves_tied_company_down() {
        let d = def();
        let mut m = Market::new(&d, 1);
        let before = m.quotes[0].value;
        let news = m.event(&d, "death:gov_x", 1.0);
        assert!(m.quotes[0].value < before * 0.85);
        assert_eq!(news.len(), 1);
        // The price follows the value over the next ticks.
        let p0 = m.quotes[0].price;
        for _ in 0..40 {
            m.step(&d);
        }
        assert!(m.quotes[0].price < p0 * 1.02);
    }

    #[test]
    fn wildcard_reaction() {
        let d = def();
        let mut m = Market::new(&d, 1);
        let before = m.quotes[1].value;
        let news = m.event(&d, "method:poison", 1.0);
        assert!(m.quotes[1].value > before * 1.09);
        assert_eq!(news, vec!["Unrest".to_string()]);
    }

    #[test]
    fn trading() {
        let d = def();
        let mut m = Market::new(&d, 1);
        let p = m.price("a").unwrap();
        m.trade("a", 10).unwrap();
        assert!((m.cash - (1000.0 - p * 10.0)).abs() < 0.01);
        assert!(m.trade("a", -11).is_err());
        m.trade("a", -10).unwrap();
        assert!((m.cash - 1000.0).abs() < 0.01);
        assert!(m.trade("a", 100000).is_err());
    }

    #[test]
    fn eighths_format() {
        assert_eq!(eighths(42.375), "42 3/8");
        assert_eq!(eighths(7.0), "7");
        assert_eq!(eighths(0.5), "0 1/2");
    }
}
