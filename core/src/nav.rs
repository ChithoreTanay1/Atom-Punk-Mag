//! Waypoint graph with A*. Levels register nodes and links; NPCs ask for a
//! route between two points. Cheaper and more predictable than a navmesh for
//! a hand-laid compound.

use std::cmp::Ordering;
use std::collections::BinaryHeap;

#[derive(Clone, Debug, Default)]
pub struct NavGraph {
    pub nodes: Vec<[f32; 3]>,
    pub links: Vec<Vec<usize>>,
}

fn dist(a: [f32; 3], b: [f32; 3]) -> f32 {
    let (dx, dy, dz) = (a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    (dx * dx + dy * dy * 4.0 + dz * dz).sqrt() // vertical moves cost more
}

#[derive(PartialEq)]
struct Open(f32, usize);
impl Eq for Open {}
impl PartialOrd for Open {
    fn partial_cmp(&self, o: &Self) -> Option<Ordering> { Some(self.cmp(o)) }
}
impl Ord for Open {
    fn cmp(&self, o: &Self) -> Ordering {
        o.0.partial_cmp(&self.0).unwrap_or(Ordering::Equal)
    }
}

impl NavGraph {
    pub fn add_node(&mut self, p: [f32; 3]) -> usize {
        self.nodes.push(p);
        self.links.push(Vec::new());
        self.nodes.len() - 1
    }

    pub fn link(&mut self, a: usize, b: usize) {
        if a == b || a >= self.nodes.len() || b >= self.nodes.len() { return; }
        if !self.links[a].contains(&b) { self.links[a].push(b); }
        if !self.links[b].contains(&a) { self.links[b].push(a); }
    }

    pub fn nearest(&self, p: [f32; 3]) -> Option<usize> {
        self.nodes
            .iter()
            .enumerate()
            .min_by(|a, b| dist(*a.1, p).partial_cmp(&dist(*b.1, p)).unwrap_or(Ordering::Equal))
            .map(|(i, _)| i)
    }

    /// Node path from `start` to `goal`, inclusive. Empty if unreachable.
    pub fn path(&self, start: usize, goal: usize) -> Vec<usize> {
        let n = self.nodes.len();
        if start >= n || goal >= n { return vec![]; }
        let mut g = vec![f32::INFINITY; n];
        let mut came = vec![usize::MAX; n];
        let mut open = BinaryHeap::new();
        g[start] = 0.0;
        open.push(Open(dist(self.nodes[start], self.nodes[goal]), start));
        while let Some(Open(_, cur)) = open.pop() {
            if cur == goal {
                let mut out = vec![goal];
                let mut c = goal;
                while c != start { c = came[c]; out.push(c); }
                out.reverse();
                return out;
            }
            for &nb in &self.links[cur] {
                let ng = g[cur] + dist(self.nodes[cur], self.nodes[nb]);
                if ng < g[nb] {
                    g[nb] = ng;
                    came[nb] = cur;
                    open.push(Open(ng + dist(self.nodes[nb], self.nodes[goal]), nb));
                }
            }
        }
        vec![]
    }

    /// World-space route between two arbitrary points via the graph.
    pub fn route(&self, from: [f32; 3], to: [f32; 3]) -> Vec<[f32; 3]> {
        let (Some(a), Some(b)) = (self.nearest(from), self.nearest(to)) else { return vec![to] };
        let mut pts: Vec<[f32; 3]> = self.path(a, b).into_iter().map(|i| self.nodes[i]).collect();
        // Skip the first node if we're already past it toward the second.
        if pts.len() >= 2 && dist(from, pts[1]) < dist(pts[0], pts[1]) { pts.remove(0); }
        pts.push(to);
        pts
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_path_around() {
        let mut g = NavGraph::default();
        let a = g.add_node([0.0, 0.0, 0.0]);
        let b = g.add_node([10.0, 0.0, 0.0]);
        let c = g.add_node([10.0, 0.0, 10.0]);
        let d = g.add_node([0.0, 0.0, 10.0]);
        g.link(a, b);
        g.link(b, c);
        g.link(c, d);
        assert_eq!(g.path(a, d), vec![a, b, c, d]);
        g.link(a, d);
        assert_eq!(g.path(a, d), vec![a, d]);
        let r = g.route([0.5, 0.0, 0.0], [0.0, 0.0, 9.0]);
        assert_eq!(*r.last().unwrap(), [0.0, 0.0, 9.0]);
    }

    #[test]
    fn unreachable_is_empty() {
        let mut g = NavGraph::default();
        let a = g.add_node([0.0; 3]);
        let b = g.add_node([1.0, 0.0, 0.0]);
        assert!(g.path(a, b).is_empty());
    }
}
