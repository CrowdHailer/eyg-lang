import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/hub/release
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/tree as ir
import gleam/crypto
import gleam/dict
import gleam/int

pub fn empty_cache_has_no_effects_test() {
  let cache = cache.empty()
  assert #(cache, []) == cache.flush(cache)
}

pub fn pull_idempotency_test() {
  let cache = cache.pull(cache.empty())

  // if lined up already pulling makes no change
  assert cache == cache.pull(cache)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.PullPackages(0) == effect

  // effect is only returned once
  assert #(cache, []) == cache.flush(cache)
  assert cache == cache.pull(cache)
}

pub fn fetch_idemotency_test() {
  let #(cid, _) = random_code()
  let cache = cache.fetch(cache.empty(), cid)

  // if lined up already fetching makes no change
  assert cache == cache.fetch(cache, cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(cid) == effect

  // effect is only returned once
  assert #(cache, []) == cache.flush(cache)
  assert cache == cache.fetch(cache, cid)
}

pub fn successful_fetch_test() {
  let num = int.random(1_000_000)
  let #(cid, source) = code(num)
  let cache = cache.fetch(cache.empty(), cid)
  assert cache.Unknown == cache.module(cache, cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(cid) == effect

  let #(cache, done) = cache.fetched(cache, cid, Ok(source))
  assert [#(cid, Ok(v.Integer(num)))] == done
  let assert cache.Available(module) = cache.module(cache, cid)
  assert cache.Module(v.Integer(num), t.Integer) == module

  assert Error(Nil) == dict.get(cache.fetching_modules, cid)
  assert cache == cache.fetch(cache, cid)
}

pub fn fetch_dependent_references_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.fetch(cache.empty(), parent_cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(parent_cid) == effect
  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert cache.Content(child_cid) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(child_cid) == effect
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  assert [
      #(parent_cid, Ok(v.Integer(num + 1))),
      #(child_cid, Ok(v.Integer(num))),
    ]
    == done
  let assert cache.Available(module) = cache.module(cache, parent_cid)
  assert cache.Module(v.Integer(num + 1), t.Integer) == module
  let assert cache.Available(module) = cache.module(cache, child_cid)
  assert cache.Module(v.Integer(num), t.Integer) == module
  assert dict.new() == cache.fetching_modules
}

pub fn already_available_reference_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  assert [#(child_cid, Ok(v.Integer(num)))] == done

  let assert cache.Available(module) = cache.module(cache, child_cid)
  assert v.Integer(num) == module.value

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert Error(Nil) == dict.get(cache.fetching_modules, parent_cid)
  assert [#(parent_cid, Ok(v.Integer(num + 1)))] == done
}

pub fn fetch_failure_will_retry_test() {
  let num = int.random(1_000_000)
  let #(cid, _source) = code(num)
  let cache = cache.fetch(cache.empty(), cid)
  assert cache.Unknown == cache.module(cache, cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(cid) == effect

  let #(cache, done) = cache.fetched(cache, cid, Error("test error"))
  assert [] == done
  assert cache.Unknown == cache.module(cache, cid)
}

pub fn invalid_reference_wont_be_refetched_test() {
  let source =
    ir.vacant()
    |> ir.map_annotation(fn(_) { [] })
  let cid = cid_from_tree(source)
  let cache = cache.empty()
  let #(cache, done) = cache.fetched(cache, cid, Ok(source))
  assert [#(cid, Error(break.Vacant))] == done
  assert cache == cache.fetch(cache, cid)
  assert #(cache, []) == cache.flush(cache)
}

pub fn fetch_dependent_invalid_references_test() {
  let child =
    ir.call(ir.perform("Zing"), [ir.unit()])
    |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert cache.Content(child_cid) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(child_cid) == effect
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))

  let reason = break.UnhandledEffect("Zing", v.unit())
  assert [#(parent_cid, Error(reason)), #(child_cid, Error(reason))] == done
  assert cache.Unavailable(reason) == cache.module(cache, parent_cid)
  assert cache.Unavailable(reason) == cache.module(cache, child_cid)
}

pub fn already_invalid_reference_cascades_to_parent_test() {
  let child =
    ir.call(ir.perform("Zing"), [ir.unit()])
    |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  let reason = break.UnhandledEffect("Zing", v.unit())
  assert [#(child_cid, Error(reason))] == done
  assert cache.Unavailable(reason) == cache.module(cache, child_cid)

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert Ok(cache.Invalid(reason))
    == dict.get(cache.fetching_modules, parent_cid)
  assert [#(parent_cid, Error(break.UnhandledEffect("Zing", v.unit())))] == done
}

pub fn failure_after_resumption_marks_module_as_invalid_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.string("not a number"))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done

  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))

  let reason = break.IncorrectTerm("Integer", v.String("not a number"))
  assert cache.Unavailable(reason) == cache.module(cache, parent_cid)
  assert cache.Available(cache.Module(v.Integer(num), t.Integer))
    == cache.module(cache, child_cid)
  assert [#(parent_cid, Error(reason)), #(child_cid, Ok(v.Integer(num)))]
    == done
}

pub fn will_resolve_references_after_resumption_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.reference(child_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done

  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))

  assert cache.Available(cache.Module(v.Integer(num + num), t.Integer))
    == cache.module(cache, parent_cid)
  assert cache.Available(cache.Module(v.Integer(num), t.Integer))
    == cache.module(cache, child_cid)
  assert [
      #(parent_cid, Ok(v.Integer(num + num))),
      #(child_cid, Ok(v.Integer(num))),
    ]
    == done
}

pub fn will_lookup_multiple_reference_test() {
  let num1 = int.random(1_000_000)
  let #(child_cid1, child1) = code(num1)
  let num2 = int.random(1_000_000)
  let #(child_cid2, child2) = code(num2)

  let parent =
    ir.add(ir.reference(child_cid1), ir.reference(child_cid2))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done

  let #(cache, done) = cache.fetched(cache, child_cid1, Ok(child1))
  assert [#(child_cid1, Ok(v.Integer(num1)))] == done
  assert cache.Available(cache.Module(v.Integer(num1), t.Integer))
    == cache.module(cache, child_cid1)
  assert cache.Unknown == cache.module(cache, parent_cid)

  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid2)] == effects

  let #(cache, done) = cache.fetched(cache, child_cid2, Ok(child2))
  assert [
      #(parent_cid, Ok(v.Integer(num1 + num2))),
      #(child_cid2, Ok(v.Integer(num2))),
    ]
    == done
  assert cache.Available(cache.Module(v.Integer(num2), t.Integer))
    == cache.module(cache, child_cid2)
  assert cache.Available(cache.Module(v.Integer(num1 + num2), t.Integer))
    == cache.module(cache, parent_cid)
}

pub fn multiple_parents_resolve_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let p1 =
    ir.add(ir.reference(child_cid), ir.integer(10))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.reference(child_cid), ir.integer(20))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)
  let cache = cache.empty()

  let #(cache, done) = cache.fetched(cache, p1_cid, Ok(p1))
  assert [] == done
  let #(cache, done) = cache.fetched(cache, p2_cid, Ok(p2))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))

  assert dict.from_list([
      #(p1_cid, Ok(v.Integer(num + 10))),
      #(p2_cid, Ok(v.Integer(num + 20))),
      #(child_cid, Ok(v.Integer(num))),
    ])
    == dict.from_list(done)

  assert dict.new() == cache.fetching_modules
}

pub fn multiple_parents_resolve_failure_test() {
  let child = ir.vacant() |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let p1 =
    ir.add(ir.reference(child_cid), ir.integer(10))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.reference(child_cid), ir.integer(20))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)
  let cache = cache.empty()

  let #(cache, done) = cache.fetched(cache, p1_cid, Ok(p1))
  assert [] == done
  let #(cache, done) = cache.fetched(cache, p2_cid, Ok(p2))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))

  assert dict.from_list([
      #(p1_cid, Error(break.Vacant)),
      #(p2_cid, Error(break.Vacant)),
      #(child_cid, Error(break.Vacant)),
    ])
    == dict.from_list(done)

  assert cache.Unavailable(break.Vacant) == cache.module(cache, child_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, p1_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, p2_cid)
}

pub fn fetching_a_module_with_invalid_dep_will_cascade_test() {
  let base = ir.vacant() |> ir.map_annotation(fn(_) { [] })
  let base_cid = cid_from_tree(base)
  let cache = cache.empty()
  let #(cache, _) = cache.fetched(cache, base_cid, Ok(base))
  assert cache.Unavailable(break.Vacant) == cache.module(cache, base_cid)

  let child = ir.reference(base_cid) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent = ir.reference(child_cid) |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  assert [#(parent_cid, Error(break.Vacant)), #(child_cid, Error(break.Vacant))]
    == done
  assert cache.Unavailable(break.Vacant) == cache.module(cache, child_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, parent_cid)
}

pub fn resuming_encountering_an_invalid_module_is_invalid_test() {
  let broken = ir.vacant() |> ir.map_annotation(fn(_) { [] })
  let broken_cid = cid_from_tree(broken)
  let cache = cache.empty()
  let #(cache, _) = cache.fetched(cache, broken_cid, Ok(broken))
  assert cache.Unavailable(break.Vacant) == cache.module(cache, broken_cid)

  let child = ir.integer(111) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.reference(broken_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects

  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  assert [#(parent_cid, Error(break.Vacant)), #(child_cid, Ok(v.Integer(111)))]
    == done
  assert cache.Available(cache.Module(v.Integer(111), t.Integer))
    == cache.module(cache, child_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, parent_cid)
}

pub fn multiple_parents_failures_after_resumption_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let p1 =
    ir.add(ir.reference(child_cid), ir.string("a"))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.reference(child_cid), ir.string("b"))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)
  let cache = cache.empty()

  let #(cache, done) = cache.fetched(cache, p1_cid, Ok(p1))
  assert [] == done
  let #(cache, done) = cache.fetched(cache, p2_cid, Ok(p2))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))

  assert dict.from_list([
      #(p1_cid, Error(break.IncorrectTerm("Integer", v.String("a")))),
      #(p2_cid, Error(break.IncorrectTerm("Integer", v.String("b")))),
      #(child_cid, Ok(v.Integer(num))),
    ])
    == dict.from_list(done)

  assert cache.Available(cache.Module(v.Integer(num), t.Integer))
    == cache.module(cache, child_cid)
  assert cache.Unavailable(break.IncorrectTerm("Integer", v.String("a")))
    == cache.module(cache, p1_cid)
  assert cache.Unavailable(break.IncorrectTerm("Integer", v.String("b")))
    == cache.module(cache, p2_cid)
}

pub fn successfully_pull_release_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.release("std", 1, child_cid), ir.release("std", 1, child_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.fetch(cache.empty(), parent_cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(parent_cid) == effect
  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert cache.Release(release.Release("std", 1, child_cid)) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)

  assert cache.PullPackages(0) == effect
  let release = release.Release("std", 1, child_cid)
  assert cache.Unknown == cache.release(cache, release)
  let #(cache, done) = cache.pulled(cache, 1, release)
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects

  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  assert [
      #(parent_cid, Ok(v.Integer(num + num))),
      #(child_cid, Ok(v.Integer(num))),
    ]
    == done

  assert cache.Available(child_cid) == cache.release(cache, release)
  assert dict.new() == cache.fetching_modules
  let release = release.Release("std", 1, child_cid)
  let #(other_cid, _) = random_code()
  let release = release.Release(..release, module: other_cid)
  assert cache.Unavailable(Nil) == cache.release(cache, release)
}

pub fn release_less_than_one_is_not_pulled_test() {
  let #(other_cid, _other) = random_code()
  let source =
    ir.release("local", 0, other_cid) |> ir.map_annotation(fn(_) { [] })

  let return = expression.execute(source, [])
  let cache = cache.empty()
  let #(_return, cache) = cache.loop(return, cache, expression.resume)
  assert #(cache, []) == cache.flush(cache)
}

pub fn successful_pull_cascades_test() {
  let num = int.random(1_000_000)
  let #(base_cid, base) = code(num)

  let child = ir.release("bar", 1, base_cid) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(100))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let bad_parent =
    ir.add(ir.reference(child_cid), ir.vacant())
    |> ir.map_annotation(fn(_) { [] })
  let bad_parent_cid = cid_from_tree(bad_parent)

  // base is already installed as a module
  let cache = cache.empty()
  let #(cache, _effects) = cache.fetched(cache, base_cid, Ok(base))
  let #(cache, _effects) = cache.fetched(cache, child_cid, Ok(child))

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done
  let #(cache, done) = cache.fetched(cache, bad_parent_cid, Ok(bad_parent))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.PullPackages(0)] == effects
  let assert Ok(cache.DependsOn(cache.Release(release), ..)) =
    dict.get(cache.fetching_modules, child_cid)
  assert release.Release("bar", 1, base_cid) == release
  let assert Ok(cache.DependsOn(cache.Content(c), ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert child_cid == c
  let #(cache, done) =
    cache.pulled(cache, 1, release.Release("bar", 1, base_cid))
  assert dict.from_list([
      #(bad_parent_cid, Error(break.Vacant)),
      #(parent_cid, Ok(v.Integer(num + 100))),
      #(child_cid, Ok(v.Integer(num))),
    ])
    == dict.from_list(done)
  assert dict.from_list([#(bad_parent_cid, cache.Invalid(break.Vacant))])
    == cache.fetching_modules
}

pub fn bad_pull_cascades_test() {
  let num = int.random(1_000_000)
  let #(base_cid, _base) = code(num)
  let #(other_cid, _other) = random_code()

  let child = ir.release("bar", 1, other_cid) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(100))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, _effects) = cache.fetched(cache, child_cid, Ok(child))

  // parent is in status fetching, it depends on child.
  // When child is invalid this error should cascade.
  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  assert [] == done
  let assert Ok(cache.DependsOn(dep, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert cache.Content(child_cid) == dep

  let assert Ok(cache.DependsOn(cache.Release(release), ..)) =
    dict.get(cache.fetching_modules, child_cid)
  assert release.Release("bar", 1, other_cid) == release

  let #(_cache, done) =
    cache.pulled(cache, 1, release.Release("bar", 1, base_cid))

  let done = dict.from_list(done)
  let reason = break.UndefinedRelease("bar", 1, other_cid)
  assert Ok(Error(reason)) == dict.get(done, child_cid)
  assert Ok(Error(reason)) == dict.get(done, parent_cid)
}

pub fn both_fail_an_invalid_parents_cascade_test() {
  let num = int.random(1_000_000)
  let #(base_cid, base) = code(num)
  let #(other_cid, _other) = random_code()
  let p1 =
    ir.add(ir.release("foo", 1, base_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.release("foo", 1, other_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)

  // base is already installed as a module so resolving the release will be able to complete
  let cache = cache.empty()
  let #(cache, _done) = cache.fetched(cache, base_cid, Ok(base))
  let #(cache, _done) = cache.fetched(cache, p1_cid, Ok(p1))
  let #(cache, _done) = cache.fetched(cache, p2_cid, Ok(p2))

  let release = release.Release("foo", 1, base_cid)
  let #(_cache, done) = cache.pulled(cache, 1, release)
  let done = dict.from_list(done)
  assert Ok(Ok(v.Integer(num + 1))) == dict.get(done, p1_cid)
  assert Ok(Error(break.UndefinedRelease("foo", 1, other_cid)))
    == dict.get(done, p2_cid)
}

pub fn resumption_to_bad_release_fails_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)
  let #(other_cid, _other) = random_code()

  let parent =
    ir.add(ir.release("std", 1, child_cid), ir.release("std", 1, other_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()

  let #(cache, done) = cache.fetched(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert cache.Release(release.Release("std", 1, child_cid)) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.PullPackages(0) == effect
  let release = release.Release("std", 1, child_cid)
  let #(cache, done) = cache.pulled(cache, 1, release)
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects

  let #(cache, done) = cache.fetched(cache, child_cid, Ok(child))
  let done = dict.from_list(done)
  assert Ok(Ok(v.Integer(num))) == dict.get(done, child_cid)
  let reason = break.UndefinedRelease("std", 1, other_cid)
  assert Ok(Error(reason)) == dict.get(done, parent_cid)

  assert dict.from_list([
      #(parent_cid, cache.Invalid(break.UndefinedRelease("std", 1, other_cid))),
    ])
    == cache.fetching_modules
}

// test resumption with bad module value in part of an addition

fn code(i) {
  let source =
    ir.integer(i)
    |> ir.map_annotation(fn(_) { [] })
  #(cid_from_tree(source), source)
}

fn random_code() {
  code(int.random(1_000_000))
}

pub fn cid_from_tree(source) {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}
