import cloud/apex/context.{Context}
import cloud/box
import cloud/box/memory
import cloud/data/boxes
import cloud/file_system
import cloud/helpers
import pog

pub fn keep_a_box_in_memory_until_a_session_is_made_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, "home")
  let assert Ok(changed) =
    box.change(context, home, file_system.write(home.root, "/a.txt", <<"a">>))
  // Nothing is in Postgres.
  let assert Ok(pog.Returned(rows: [], ..)) =
    pog.execute(boxes.latest("home"), context.db)
  let assert Error(box.Conflict) = box.create(context, "home")
  // A service started again has its own memory, so the box is lost.
  let assert Ok(memory) = memory.start()
  let restarted = Context(..context, memory: memory.data)
  let assert Error(box.Missing) = box.latest(restarted, "home")

  // The first session makes the box durable, with every event it had in memory.
  let assert Ok(Nil) = box.durable(context, "home")
  assert Ok(changed) == box.latest(restarted, "home")
  assert 2 == changed.sequence
  let assert Ok(Nil) = box.durable(context, "home")
  let assert Error(box.Conflict) = box.create(restarted, "home")
}
