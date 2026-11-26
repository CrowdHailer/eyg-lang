import howdy/controller

pub fn route(_context) {
  controller.new("/")
  |> controller.build
}
