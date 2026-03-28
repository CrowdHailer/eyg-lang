import hub
import mist/reload

pub fn main() {
  hub.start("development", reload.wrap)
}
