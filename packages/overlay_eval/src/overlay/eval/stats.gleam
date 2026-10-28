//// Statistics for eval results.
////
//// Scores are means over tasks. Trials of one task are not independent, so
//// errors are computed from per task means, which clusters trials by task.
//// Comparisons pair results on the same tasks, which removes the variation
//// between tasks from the difference.
////
//// See "Adding Error Bars to Evals" (Miller, 2024) for the approach and
//// "Evaluating Large Language Models Trained on Code" (Chen et al., 2021) for
//// the pass@k estimator.

import gleam/float
import gleam/int
import gleam/list

/// A mean with its standard error.
pub type Estimate {
  Estimate(mean: Float, standard_error: Float, samples: Int)
}

/// The chance at least one of k trials passes, estimated without bias from
/// `passes` of `trials`.
pub fn pass_at_k(trials: Int, passes: Int, k: Int) -> Float {
  case trials - passes < k {
    True -> 1.0
    False -> 1.0 -. ratio(trials - passes, trials, k)
  }
}

/// The chance all of k trials pass, estimated without bias from `passes` of
/// `trials`. This is the reliability of an agent, pass^k.
pub fn pass_power_k(trials: Int, passes: Int, k: Int) -> Float {
  case passes < k {
    True -> 0.0
    False -> ratio(passes, trials, k)
  }
}

/// C(a, k) / C(b, k) without large numbers.
fn ratio(a, b, k) {
  int.range(from: 0, to: k, with: 1.0, run: fn(acc, i) {
    acc *. int.to_float(a - i) /. int.to_float(b - i)
  })
}

pub fn mean(values: List(Float)) -> Float {
  case values {
    [] -> 0.0
    _ -> float.sum(values) /. int.to_float(list.length(values))
  }
}

/// The mean and its standard error, from the sample standard deviation.
pub fn estimate(values: List(Float)) -> Estimate {
  let samples = list.length(values)
  let mean = mean(values)
  let standard_error = case samples {
    0 | 1 -> 0.0
    _ -> {
      let variance =
        list.fold(values, 0.0, fn(acc, value) {
          acc +. { value -. mean } *. { value -. mean }
        })
        /. int.to_float(samples - 1)
      let assert Ok(deviation) = float.square_root(variance)
      let assert Ok(root) = float.square_root(int.to_float(samples))
      deviation /. root
    }
  }
  Estimate(mean:, standard_error:, samples:)
}

/// The 95% confidence interval, from the normal approximation.
pub fn interval(estimate: Estimate) -> #(Float, Float) {
  let margin = 1.96 *. estimate.standard_error
  #(estimate.mean -. margin, estimate.mean +. margin)
}

/// The difference `a - b` of paired values, with its standard error.
pub fn paired(pairs: List(#(Float, Float))) -> Estimate {
  estimate(list.map(pairs, fn(pair) { pair.0 -. pair.1 }))
}

/// True when the 95% interval of a difference excludes zero.
pub fn significant(difference: Estimate) -> Bool {
  let #(low, high) = interval(difference)
  difference.samples > 1 && { low >. 0.0 || high <. 0.0 }
}

/// A rate as a percentage with no decimal places, `0.456` is `46%`.
pub fn percent(rate: Float) -> String {
  int.to_string(float.round(rate *. 100.0)) <> "%"
}

/// A difference as signed percentage points, `0.1` is `+10pp`.
pub fn points(difference: Float) -> String {
  let points = float.round(difference *. 100.0)
  case points > 0 {
    True -> "+" <> int.to_string(points) <> "pp"
    False -> int.to_string(points) <> "pp"
  }
}
