import gleam/bit_string
import gleam/io
import gleam/list

// Maybe rename parser
pub type State {
  Initial
  Major
  Minor(major: Int)
  Sysex
  SxReportFirmware(payload: BitString)
}

pub type Message {
    ProtocolVersion(major: Int, minor: Int)
    ReportFirmware(payload: String)
}


pub fn fresh() {
    #(Initial, [])
}



pub fn parse(bytes, state, received) {
  case bytes {
    <<>> -> #(state, list.reverse(received))
    <<next, rest:binary>> ->
      case state, next {
        Initial, 0xF9 -> parse(rest, Major, received)
        Major, major -> parse(rest, Minor(major), received)
        Minor(major), minor -> parse(rest, Initial, [ProtocolVersion(major, minor), ..received])
        Initial, 0xF0 -> parse(rest, Sysex, received)
        Sysex, 0x79 -> parse(rest, SxReportFirmware(<<>>), received)
        SxReportFirmware(bytes), 0xF7 -> {
            io.debug(bytes)
            assert Ok(report) = bit_string.to_string(bytes)
            let message = ReportFirmware(report)
            parse(rest, Initial, [message, ..received])
        }
        SxReportFirmware(bytes), byte -> parse(rest, SxReportFirmware(<<byte, bytes:bits>>), received)
        _, _ -> #(state, received)
      }
  }
}


