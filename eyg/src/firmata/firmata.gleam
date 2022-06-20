import gleam/bit_string
import gleam/bitwise
import gleam/io
import gleam/list

// Maybe rename parser
pub type State {
  Initial
  Major
  Minor(major: Int)
  Sysex(bytes: BitString)
}

pub type Message {
  Firmware(name: String, version: #(Int, Int))
  Capabilities(List(List(Mode)))
  PinState
}

// pub fn report_digital_pin() -> Nil {
//   todo
// }

const start_sysex = 0xF0

const end_sysex = 0xF7

const report_version = 0xF9

pub fn fresh() {
  #(Initial, [])
}

// TODO alternative to firmata/ ask in the rust forum
pub fn parse(bytes, state, received) {
  case bytes {
    <<>> -> #(state, list.reverse(received))
    <<next, rest:binary>> ->
      case state, next {
        Initial, byte if byte == report_version -> parse(rest, Major, received)
        Major, major -> parse(rest, Minor(major), received)
        Minor(major), minor -> {
          let version = #(major, minor)
          let message = Firmware("", version)
          parse(rest, Initial, [message, ..received])
        }
        Initial, byte if byte == start_sysex ->
          parse(rest, Sysex(<<>>), received)
        Sysex(bytes), byte if byte == end_sysex -> {
          let message = parse_sysex(bytes)
          let received = [message, ..received]
          parse(rest, Initial, received)
        }
        Sysex(bytes), b -> parse(rest, Sysex(<<bytes:bit_string, b>>), received)
        Initial, byte if 0x90 <= byte && byte <= 0x9F -> {
          let <<lsb, msb, rest:binary>> = rest
          let port = byte - 0x90
          bitwise.shift_left(msb, 7)
          |> io.debug
          io.debug(lsb)
          io.debug(msb)
          // let <<_:1, _:1, a:1, b:1, c:1, d:1, e:1, f:1, bi:binary>> = <<lsb>>
          // let <<_:1, _:1, _:1, _:1, _:1, _:1, g:1, h:1>> = <<msb>>
          // io.debug(g)
          // io.debug(h)
          // TODO not pinstate
          PinState
          parse(rest, Initial, received)
        }
        _, _ -> {
          io.debug(bytes)
          todo("handle this cae")
        }
      }
  }
}

const report_firmware = 0x79

const capability_response = 0x6c

const pin_state_response = 0x6e

fn parse_sysex(bytes) {
  case bytes {
    <<control, major, minor, name:binary>> if control == report_firmware -> {
      assert Ok(name) = name_from_bytes(name)
      let version = #(major, minor)
      Firmware(name, version)
    }
    <<control, capabilities:binary>> if control == capability_response -> {
      let capabilities = parse_capabilities(capabilities)
      Capabilities(capabilities)
    }
    <<control, pin, mode, state:binary>> if control == pin_state_response -> {
      io.debug(pin)
      io.debug(mode)
      io.debug(state)
      // todo("pin state")
      PinState
    }
    _ -> {
      io.debug(bytes)
      todo("really weired")
    }
  }
}

fn do_name_from_bytes(bytes, buffer) {
  case bytes {
    <<>> -> bit_string.to_string(buffer)
    <<lsb, 0, rest:binary>> ->
      do_name_from_bytes(rest, <<buffer:bit_string, lsb>>)
  }
}

fn name_from_bytes(bytes) {
  do_name_from_bytes(bytes, <<>>)
}

pub type Mode {
  DigitalInput
  DigitalOutput
  AnalogInput
  Pwm
  Servo
  Shift
  I2c
  Onewire
  Stepper
  Encoder
  Serial
  InputPullup
}

fn do_parse_capabilities(rest, acc) {
  let #(current, pins) = acc
  case rest {
    <<127>> -> list.reverse(pins)
    <<127, next:binary>> ->
      do_parse_capabilities(next, #([], [current, ..pins]))
    <<mode, resolution, rest:binary>> -> {
      let x = case mode {
        0x00 -> DigitalInput
        0x01 -> DigitalOutput
        0x02 -> AnalogInput
        0x03 -> Pwm
        0x04 -> Servo
        0x05 -> Shift
        0x06 -> I2c
        0x07 -> Onewire
        0x08 -> Stepper
        0x09 -> Encoder
        0x0A -> Serial
        0x0B -> InputPullup
      }
      let current = [x, ..current]
      do_parse_capabilities(rest, #(current, pins))
    }
  }
}

fn parse_capabilities(raw) {
  do_parse_capabilities(raw, #([], []))
}
