import gleam/float
import overlay/eval/stats

fn close(a, b) {
  float.loosely_equals(a, b, tolerating: 0.0001)
}

pub fn pass_at_k_test() {
  assert close(0.3, stats.pass_at_k(10, 3, 1))
  // 1 - C(7, 2) / C(10, 2)
  assert close(1.0 -. 21.0 /. 45.0, stats.pass_at_k(10, 3, 2))
  assert 1.0 == stats.pass_at_k(10, 9, 2)
  assert 0.0 == stats.pass_at_k(10, 0, 5)
}

pub fn pass_power_k_test() {
  assert close(0.3, stats.pass_power_k(10, 3, 1))
  // C(3, 2) / C(10, 2)
  assert close(3.0 /. 45.0, stats.pass_power_k(10, 3, 2))
  assert 1.0 == stats.pass_power_k(4, 4, 4)
  assert 0.0 == stats.pass_power_k(10, 3, 4)
}

pub fn estimates_have_standard_errors_test() {
  let estimate = stats.estimate([1.0, 0.0, 1.0, 0.0])
  assert close(0.5, estimate.mean)
  assert close(0.2887, estimate.standard_error)
  assert 4 == estimate.samples
  let #(low, high) = stats.interval(estimate)
  assert close(0.5 -. 1.96 *. 0.2887, low)
  assert close(0.5 +. 1.96 *. 0.2887, high)
  assert 0.0 == stats.estimate([1.0]).standard_error
  assert 0.0 == stats.estimate([]).mean
}

pub fn paired_differences_test() {
  assert !stats.significant(stats.paired([#(1.0, 0.0)]))
  let difference = stats.paired([#(1.0, 0.0), #(1.0, 1.0), #(0.0, 0.0)])
  assert close(1.0 /. 3.0, difference.mean)
  assert close(1.0 /. 3.0, difference.standard_error)
  assert !stats.significant(difference)
  let clear = stats.paired([#(1.0, 0.0), #(1.0, 0.0), #(0.9, 0.0), #(1.0, 0.1)])
  assert stats.significant(clear)
}

pub fn formatting_test() {
  assert "46%" == stats.percent(0.456)
  assert "+10pp" == stats.points(0.1)
  assert "-5pp" == stats.points(-0.05)
  assert "0pp" == stats.points(0.0)
}
