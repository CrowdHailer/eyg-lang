import eyg_pi/build
import eyg_pi/frame
import eyg_pi/machine as m
import filepath
import gleam/io
import gleam/javascript/promise
import gleam/string
import simplifile

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let assert Ok(_) = simplifile.create_directory_all("build/screens")
  use machine <- promise.await(m.start(True))
  let checked =
    {
      use _ <- promise.await(m.wait_for(machine.output, "\n> ", 0, 3000))
      use before <- promise.await(m.wait_screen(
        machine,
        filepath.join(cwd, "build/screens/hdmi-boot.ppm"),
        fn(bytes) { frame.lit(frame.decode(bytes), 0, 0, True) > 0 },
        120,
      ))
      let image = frame.decode(before)
      io.println(
        "HDMI framebuffer: " <> string.inspect(#(image.width, image.height)),
      )
      assert frame.lit(image, 0, 0, True) > 0
      use _ <- promise.await(m.type_keys(machine, "!int_multiply(6, 7)\n"))
      use _ <- promise.await(m.response(machine, "perform Sleep(2000)", "\n> "))
      use after <- promise.await(m.screenshot(
        machine,
        filepath.join(cwd, "build/screens/hdmi-shell.ppm"),
      ))
      assert after != before
      let image = frame.decode(after)
      assert frame.lit(image, 0, 2, True) > 0
        && frame.lit(image, 1, 2, True) > 0
        as "The result must occupy two HDMI character cells"
      use _ <- promise.map(
        build.command(".", "ffmpeg", [
          "-v",
          "error",
          "-y",
          "-i",
          "build/screens/hdmi-shell.ppm",
          "build/screens/hdmi-shell.png",
        ]),
      )
      io.println("PASS real HDMI keyboard input and changed framebuffer")
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.map(m.stop(machine))
  let assert Ok(_) = checked
}
