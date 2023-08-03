import gleam/javascript/promise
import plinth/javascript/global

pub fn wait(delay) {
  promise.new(fn(resolve) { global.set_timeout(resolve, delay) })
}
