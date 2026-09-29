/// Integer slots prevent an input at or past the interval boundary. Late
/// deadlines are skipped, never replayed in a burst.
pub struct Schedule {
    pub planned: u32,
    pub next: u32,
    pub missed: u32,
    pub period_ms: f64,
}
impl Schedule {
    pub fn new(seconds: f64, rate: u32) -> Self {
        Self {
            planned: (seconds * rate as f64) as u32,
            next: 0,
            missed: 0,
            period_ms: if rate == 0 {
                f64::INFINITY
            } else {
                1000.0 / rate as f64
            },
        }
    }
    pub fn deadline(&self) -> f64 {
        self.next as f64 * self.period_ms
    }
    pub fn due(&mut self, elapsed_ms: f64) -> Option<f64> {
        if self.next >= self.planned || elapsed_ms < self.deadline() {
            return None;
        }
        let skipped = ((elapsed_ms - self.deadline()) / self.period_ms).floor() as u32;
        let skipped = skipped.min(self.planned - self.next);
        self.next += skipped;
        self.missed += skipped;
        if self.next >= self.planned {
            return None;
        }
        let deadline = self.deadline();
        self.next += 1;
        Some(deadline)
    }
    pub fn can_sample(&self, elapsed_ms: f64) -> bool {
        self.next >= self.planned || self.deadline() - elapsed_ms > 8.0
    }
}
pub fn self_test() {
    let mut s = Schedule::new(2.0, 5);
    assert_eq!(s.due(0.0), Some(0.0));
    assert_eq!(s.due(199.0), None);
    assert_eq!(s.due(620.0), Some(600.0));
    assert_eq!(s.missed, 2);
    assert!(!s.can_sample(795.0));
    assert_eq!(s.due(2000.0), None);
    assert_eq!(s.next, 10);
    let mut idle = Schedule::new(2.0, 0);
    assert_eq!(idle.due(0.0), None);
    for rate in [1, 5, 30, 60] {
        let mut s = Schedule::new(2.0, rate);
        let inputs: Vec<_> = (0..2000).filter_map(|ms| s.due(ms as f64)).collect();
        assert_eq!(inputs.len(), (2 * rate) as usize);
        assert!(inputs.iter().all(|ms| *ms < 2000.0));
    }
}
#[test]
fn scheduler_contract() {
    self_test();
}
