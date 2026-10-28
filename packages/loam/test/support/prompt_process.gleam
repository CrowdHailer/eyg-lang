import gleam/option.{Some}
import loam/system

pub fn main() {
  {
    use mode <- system.then(system.env("EYG_PROMPT_CHECK"))
    use first <- system.then(system.prompt("first> "))
    case mode {
      Some("invalid") -> {
        assert first == Error(Nil)
        system.stdout("PASS invalid UTF-8 returns an input error")
      }
      _ -> {
        assert first == Ok("one🌱")
        use second <- system.then(system.prompt("second> "))
        assert second == Ok("two")
        case mode {
          Some("remaining") -> {
            use rest <- system.then(system.stdin())
            assert rest == Ok("remaining🌱")
            system.stdout("PASS prompts leave remaining stdin bytes intact")
          }
          _ -> {
            use last <- system.then(system.prompt("last> "))
            assert last == Ok("last🌱")
            use eof <- system.then(system.prompt("eof> "))
            assert eof == Error(Nil)
            system.stdout("PASS partial final line and EOF")
          }
        }
      }
    }
  }
  |> system.run
}
