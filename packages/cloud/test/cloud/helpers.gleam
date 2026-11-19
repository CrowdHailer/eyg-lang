import cloud/apex/context.{Context}
import cloud/apex/router
import cloud/beam/execute
import cloud/box/memory
import cloud/data/blobs
import eyg/hub/cache
import gleam/dict
import ogre/origin
import simplifile

/// Each context keeps its own boxes in memory.
pub fn context(then) {
  let assert Ok(memory) = memory.start()
  let assert Ok(code) = simplifile.read("policy.eyg")
  let assert #(Ok(policy), state) = execute.load_policy(code, state())
  then(Context(memory: memory.data, state:, policy:))
}

/// Each state has its own blobs, kept in memory.
pub fn state() {
  let assert Ok(blobs) = blobs.start()
  execute.State(origin.https("eyg.test"), cache.ready(), dict.new(), blobs.data)
}

pub fn dispatch(request, context) {
  router.route(request, context)
}
