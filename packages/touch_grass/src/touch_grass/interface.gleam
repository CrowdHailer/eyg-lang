import eyg/analysis/type_/binding
import eyg/interpreter/break
import eyg/interpreter/value as v

pub type Interface(t, a, b) {
  Interface(
    name: String,
    lift_type: binding.Mono,
    lower_type: binding.Mono,
    decode: fn(v.Value(a, b)) -> Result(t, break.Reason(a, b)),
  )
}
