//// The morph `repl` is a platform agnostic set of utilities for building REPL style applications.

import eyg/hub/cache
import eyg/interpreter/state as istate

/// The status of an in progress run of an EYG program.
/// 
/// There is no success case as a successful run is moved onto the history.
/// The Exception and Aborted/Cancelled case is here as a user might want to rerun one.
pub type Run(meta) {
  Exception(istate.Reason(meta))
  Aborted(String)
  Handling(task_id: Int, env: istate.Env(meta), k: istate.Stack(meta))
  Blocked(dep: cache.Dependency, env: istate.Env(meta), k: istate.Stack(meta))
}
