import gleam/io
import gleam/javascript/promise
import plinth/browser/document
import plinth/browser/serial

pub fn run() {
  document.add_event_listener(
    "click",
    fn(_event) {
      promise.await(
        serial.request_port(),
        fn(port) {
          let assert Ok(port) =
            port
            |> io.debug()
          let info = serial.get_info(port)
          io.debug(info)
          use _ <- promise.map(serial.open(port, 9600))

          serial.read(
            port,
            fn(x) {
              io.debug(#("foo", x))
              Nil
            },
          )
          Nil
        },
      )
      Nil
    },
  )
}
