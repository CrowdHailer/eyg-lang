//// Prepare once, fork cheaply, execute with a single external broker.

import eyg/cli/internal/checkpoint
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/traces
import eyg/cli/overlay
import eyg/cli/record as cli_record
import eyg/ir/tree as ir
import glasshouse/archive
import glasshouse/bundle
import glasshouse/cohort
import glasshouse/data
import glasshouse/diff
import glasshouse/lock
import glasshouse/recorder
import glasshouse/run
import glasshouse/session
import glasshouse/store
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/acquire
import loam/broker
import loam/environment
import loam/execute
import loam/package
import loam/pin
import loam/platform/computer
import loam/prepare
import loam/record
import loam/source
import loam/system
import loam/virtual

pub type Kind {
  Block
  Agent
}

pub opaque type Prepared {
  Prepared(
    input: bundle.Bundle,
    environment: environment.Environment,
    state: execute.State,
  )
}

/// Decode and preload once for a pool of agents. Every fork shares these values.
pub fn ready(input: bundle.Bundle) -> Result(Prepared, String) {
  use input <- result.try(bundle.validate(input, traces.sha256))
  use environment <- result.map(environment.open(input))
  Prepared(
    input,
    environment,
    environment.execution_state(environment, environment.hub),
  )
}

pub fn prepare(
  directory: String,
  entry: String,
  output: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use acquired <- system.then(acquire.local(
    directory,
    [".git", ".eyg", ".env.eyg"],
    traces.sha256,
  ))
  use acquired <- system.try(acquired)
  use prepared <- system.then(prepare.prepare(
    acquired,
    entry,
    config.client.origin,
    traces.sha256,
  ))
  use prepared <- system.try(prepared)
  use written <- system.then(system.write_file(
    output,
    bundle.to_string(prepared),
  ))
  use Nil <- system.try(written)
  use Nil <- system.map(system.stdout(prepared.root))
  Ok(0)
}

pub fn load(path: String) -> system.Effect(Result(bundle.Bundle, String)) {
  use text <- system.map(system.read_file(path))
  result.try(text, bundle.from_string(_, traces.sha256))
}

pub fn package(
  path: String,
  output: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use input <- system.then(load(path))
  use input <- system.try(input)
  use prepared <- system.then(package.prepare(input, config.client.origin))
  use prepared <- system.try(prepared)
  use written <- system.then(system.write_file(
    output,
    bundle.to_string(prepared),
  ))
  use Nil <- system.try(written)
  system.Done(Ok(0))
}

pub fn execute(
  path: String,
  entry: String,
  output: String,
  kind: Kind,
  prompts: List(String),
  hosts: List(String),
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use input <- system.then(load(path))
  use input <- system.try(input)
  execute_input(input, entry, output, kind, prompts, hosts, config)
}

pub fn start(
  path: String,
  output: String,
  prompt: String,
  authorities: List(String),
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use code <- system.then(source.read_input(source.File(path)))
  use code <- system.try(code)
  use input <- system.then(prepare.configuration(
    code,
    config.client.origin,
    traces.sha256,
  ))
  use input <- system.try(input)
  execute_input(
    input,
    ".overlay.eyg",
    output,
    Agent,
    [prompt],
    authorities,
    config,
  )
}

fn execute_input(
  input: bundle.Bundle,
  entry: String,
  output: String,
  kind: Kind,
  prompts: List(String),
  hosts: List(String),
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use now <- system.then(system.now())
  use id <- system.then(traces.new_id(now))
  use archive <- system.then(run(
    input,
    entry,
    kind,
    prompts,
    broker.Live(hosts),
    id,
    config,
  ))
  use archive <- system.try(archive)
  use written <- system.then(traces.save_shared(archive, output))
  use path <- system.try(written)
  use Nil <- system.then(system.write_stdout(terminal(archive)))
  let failures =
    session.runs(archive.session)
    |> list.filter_map(fn(run) {
      case run.outcome {
        run.Failed(reason) | run.Rejected(reason) -> Ok(reason)
        _ -> Error(Nil)
      }
    })
  use Nil <- system.then(case failures {
    [] -> system.Done(Nil)
    _ -> system.write_stderr(string.join(failures, "\n") <> "\n")
  })
  use Nil <- system.map(system.stdout("saved sandbox run to " <> path))
  Ok(status(archive))
}

/// The agent-independent execution entry point. The bundle's code, filesystem,
/// environment and deterministic clock/random state are the only local inputs.
pub fn run(
  input: bundle.Bundle,
  entry: String,
  kind: Kind,
  prompts: List(String),
  mode: broker.Mode,
  id: String,
  config: config.Config,
) -> system.Effect(Result(archive.Archive, String)) {
  use prepared <- system.try(ready(input))
  fork(prepared, entry, kind, prompts, mode, id, config)
}

pub fn fork(
  prepared: Prepared,
  entry: String,
  kind: Kind,
  prompts: List(String),
  mode: broker.Mode,
  id: String,
  config: config.Config,
) -> system.Effect(Result(archive.Archive, String)) {
  let Prepared(input, environment, state) = prepared
  let config =
    config.Config(
      ..config,
      styled: False,
      client: client.Client(origin: environment.hub),
    )
  let machine =
    virtual.fork(environment)
    |> virtual.with_prompts(prompts)
    |> virtual.with_broker(mode)
  use entry <- system.try(
    system.resolve_relative(environment.cwd, entry)
    |> result.replace_error("invalid entry path"),
  )
  let source = source.File(entry)
  let progress = checkpoint.new(None)
  let program = case kind {
    Block -> block(source, environment, state, id)
    Agent -> agent(source, state, id, config, progress)
  }
  use #(outcome, machine) <- system.map(virtual.run(program, machine))
  let archive = case outcome {
    Ok(Ok(archive)) -> archive
    Error(reason) | Ok(Error(reason)) ->
      failed(environment, id, reason, checkpoint.read(progress))
  }
  let archive = mark_sources(archive, list.reverse(machine.broker.sources))
  let executions = session.runs(archive.session)
  let locked =
    list.fold(executions, environment.lock, fn(locked, run) {
      lock.merge(locked, run.lock)
    })
  let programs =
    list.fold(executions, environment.programs, fn(programs, run) {
      case run.program {
        None -> programs
        Some(program) -> {
          let name = case run.origin {
            run.File(path) -> path
            _ -> "program:" <> program
          }
          dict.insert(programs, name, program)
        }
      }
    })
  let output =
    environment.seal_fork(
      environment.Environment(
        ..environment,
        files: machine.file_system,
        clock: machine.clock,
        seed: machine.seed,
        store: store.merge(machine.artifact_store, archive.store),
        artifacts: machine.artifact_roots,
        lock: locked,
        programs:,
      ),
      environment,
      input,
      traces.sha256,
    )
  let blocks = store.merge(input.store, output.store)
  let #(blocks, observations) = broker.save(machine.broker, blocks)
  let text = string.join(list.reverse(machine.output), "")
  let #(blocks, terminal) =
    store.put_binary(blocks, <<text:utf8>>, traces.sha256)
  let #(blocks, root) =
    store.put_node(
      blocks,
      data.record([
        #("input", data.link(input.root)),
        #("output", data.link(output.root)),
        #("observations", data.link(observations)),
        #("terminal", data.link(terminal)),
        #("entry", #(ir.String(entry), Nil)),
        #(
          "kind",
          #(
            ir.String(case kind {
              Block -> "block"
              Agent -> "agent"
            }),
            Nil,
          ),
        ),
        #(
          "prompts",
          list.index_map(prompts, fn(prompt, index) {
            #(int.to_string(index), #(ir.String(prompt), Nil))
          })
            |> data.record,
        ),
      ]),
      traces.sha256,
    )
  Ok(archive.with_sandbox(archive, root, blocks))
}

fn mark_sources(
  archive: archive.Archive,
  sources: List(#(String, Bool)),
) -> archive.Archive {
  let #(_, events) =
    list.fold(archive.session.events, #(sources, []), fn(acc, event) {
      let #(sources, events) = acc
      case event {
        session.Generated(generation) -> {
          let remaining =
            list.drop_while(sources, fn(source) { source.0 != generation.key })
          case remaining {
            [#(_, reused), ..rest] -> {
              let source = case reused {
                True -> session.Recorded
                False -> session.Live
              }
              #(rest, [
                session.Generated(session.Generation(..generation, source:)),
                ..events
              ])
            }
            [] -> #(sources, [event, ..events])
          }
        }
        _ -> #(sources, [event, ..events])
      }
    })
  archive.Archive(
    ..archive,
    session: session.Session(..archive.session, events: list.reverse(events)),
  )
}

fn failed(
  environment: environment.Environment,
  id: String,
  reason: String,
  progress: option.Option(overlay.Trace),
) -> archive.Archive {
  let run =
    run.Run(
      id: "sandbox",
      kind: run.Tool("sandbox"),
      code: "",
      origin: run.Inline,
      program: None,
      lock: lock.empty(),
      cwd: environment.cwd,
      journal: [],
      outcome: run.Failed(cohort.unreproducible(reason)),
      started: environment.clock,
      ended: environment.clock,
    )
  let #(events, agent, blocks) = case progress {
    Some(trace) -> #(
      list.append(list.reverse(trace.events), [session.Execution(run)]),
      Some(trace.agent),
      recorder.store(trace.recorder),
    )
    None -> #([session.Execution(run)], None, environment.store)
  }
  archive.new(
    session.Session(
      id,
      environment.clock,
      environment.clock,
      environment.cwd,
      agent,
      events,
    ),
    blocks,
  )
}

fn agent(input, state, id, config, progress) {
  use #(session, state) <- system.then(overlay.setup(
    input,
    config,
    computer.effects(),
    overlay.rule_mapping,
    state,
  ))
  use session <- system.try(session)
  let session = overlay.Session(..session, persist: False)
  let trace = overlay.start_trace(id, session)
  let trace =
    overlay.Trace(..trace, observe: fn(trace) {
      checkpoint.write(progress, Some(trace))
    })
  checkpoint.write(progress, Some(trace))
  use trace <- system.then(overlay.outer_loop(session, state, [], trace))
  use ended <- system.map(system.now())
  Ok(overlay.to_archive(session, trace, ended))
}

fn block(
  input: source.Input,
  environment: environment.Environment,
  state: execute.State,
  id: String,
) {
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use node <- system.try(source.parse_input(code, input))
  let recorder =
    recorder.new(traces.sha256) |> recorder.with_store(environment.store)
  use #(pinned, _, recorder) <- system.then(pin.pin(
    node,
    environment.cwd,
    state,
    recorder,
    pin.allow,
  ))
  use pinned <- system.try(pinned)
  use #(outcome, recorder, Nil) <- system.then(record.run_block(
    node,
    [],
    pinned,
    environment.cwd,
    recorder,
    record.computer,
    Nil,
  ))
  let #(outcome, _, recorder) =
    cli_record.conclude(
      outcome,
      cli_record.Block,
      recorder,
      environment.cwd,
      node.1,
    )
  let run =
    run.Run(
      id:,
      kind: run.Block,
      code:,
      origin: run.File(case input {
        source.File(path) -> path
        _ -> ""
      }),
      program: Some(pinned.program),
      lock: pinned.lock,
      cwd: environment.cwd,
      journal: recorder.journal(recorder),
      outcome:,
      started: environment.clock,
      ended: environment.clock,
    )
  system.Done(
    Ok(archive.new(
      session.Session(
        id,
        environment.clock,
        environment.clock,
        environment.cwd,
        None,
        [session.Execution(run)],
      ),
      recorder.store(recorder),
    )),
  )
}

pub fn inputs(
  archive: archive.Archive,
) -> Result(#(bundle.Bundle, List(broker.Exchange)), String) {
  use root <- result.try(case archive.sandbox {
    None ->
      Error(
        "this trace has no sealed environment; prepare and record it with eyg sandbox",
      )
    Some(root) -> Ok(root)
  })
  use descriptor <- result.try(store.get_node(archive.store, root))
  use input <- result.try(
    data.field(descriptor, "input") |> result.try(data.reference),
  )
  use observations <- result.try(
    data.field(descriptor, "observations") |> result.try(data.reference),
  )
  use observations <- result.map(broker.load(observations, archive.store))
  #(bundle.new(input, archive.store), observations)
}

/// Replay the complete execution, including configuration and model requests.
pub fn replay(
  path: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use recorded <- system.then(traces.load(path))
  use recorded <- system.try(recorded)
  use #(input, observations) <- system.try(inputs(recorded))
  use #(entry, kind) <- system.try(entry(recorded))
  use replayed <- system.then(run(
    input,
    entry,
    kind,
    prompts(recorded),
    broker.Replay(observations),
    recorded.session.id,
    config,
  ))
  use replayed <- system.try(replayed)
  // Besides consuming every external observation, verify the complete EYG
  // journal/results and the final immutable filesystem/environment.
  let same =
    list.map(session.runs(recorded.session), fn(run) {
      #(run.program, run.journal, run.outcome)
    })
    == list.map(session.runs(replayed.session), fn(run) {
      #(run.program, run.journal, run.outcome)
    })
  use Nil <- system.try(case same && recorded.sandbox == replayed.sandbox {
    True -> Ok(Nil)
    False ->
      Error("sandbox replay produced a different journal or output environment")
  })
  use Nil <- system.map(system.stdout("sandbox replay matched"))
  Ok(0)
}

pub fn entry(archive: archive.Archive) -> Result(#(String, Kind), String) {
  use descriptor <- result.try(descriptor(archive))
  use entry <- result.try(
    data.field(descriptor, "entry") |> result.try(data.text),
  )
  use kind <- result.try(
    data.field(descriptor, "kind") |> result.try(data.text),
  )
  case kind {
    "block" -> Ok(#(entry, Block))
    "agent" -> Ok(#(entry, Agent))
    _ -> Error("unsupported sandbox entry kind")
  }
}

pub fn prompts(archive: archive.Archive) -> List(String) {
  let parsed = {
    use descriptor <- result.try(descriptor(archive))
    use fields <- result.try(
      data.field(descriptor, "prompts") |> result.try(data.fields),
    )
    use prompts <- result.try(
      list.try_map(fields, fn(field) {
        use index <- result.try(
          int.parse(field.0) |> result.replace_error("invalid prompt index"),
        )
        use text <- result.map(data.text(field.1))
        #(index, text)
      }),
    )
    Ok(
      prompts
      |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
      |> list.map(fn(pair) { pair.1 }),
    )
  }
  result.unwrap(parsed, [])
}

fn descriptor(archive: archive.Archive) {
  use root <- result.try(option.to_result(
    archive.sandbox,
    "trace has no sandbox",
  ))
  store.get_node(archive.store, root)
}

fn terminal(archive: archive.Archive) -> String {
  let text = {
    use descriptor <- result.try(descriptor(archive))
    use root <- result.try(
      data.field(descriptor, "terminal") |> result.try(data.reference),
    )
    use bytes <- result.try(store.get_binary(archive.store, root))
    bit_array.to_string(bytes) |> result.replace_error("invalid terminal text")
  }
  result.unwrap(text, "")
}

pub fn status(archive: archive.Archive) -> Int {
  case
    list.any(session.runs(archive.session), fn(run) {
      case run.outcome {
        run.Failed(_) | run.Rejected(_) -> True
        run.Exited(status) -> status != 0
        _ -> False
      }
    })
    || list.any(session.generations(archive.session), fn(generation) {
      generation.error != None
    })
  {
    True -> 1
    False -> 0
  }
}

/// Compare actual trees, including files that were overwritten without a read.
pub fn summarize(name: String, archive: archive.Archive) -> cohort.Summary {
  let summary = cohort.summarize(name, archive.session, archive.store)
  let trees = {
    use descriptor <- result.try(descriptor(archive))
    list.try_map(["input", "output"], fn(field) {
      use root <- result.try(
        data.field(descriptor, field) |> result.try(data.reference),
      )
      use environment <- result.map(
        environment.open(bundle.new(root, archive.store)),
      )
      environment.contents(environment.files)
    })
  }
  case trees {
    Ok([before, after]) -> {
      let changes =
        list.append(dict.keys(before), dict.keys(after))
        |> list.unique
        |> list.sort(string.compare)
        |> list.filter_map(fn(path) {
          let a = dict.get(before, path)
          let b = dict.get(after, path)
          case a == b {
            True -> Error(Nil)
            False -> {
              let text = fn(bytes) {
                bytes
                |> result.unwrap(<<>>)
                |> bit_array.to_string
                |> result.unwrap("")
              }
              let #(added, removed) = diff.stats(diff.lines(text(a), text(b)))
              Ok(cohort.Change(path, added, removed))
            }
          }
        })
      cohort.Summary(..summary, changes:)
    }
    _ -> summary
  }
}

pub fn export(
  path: String,
  output: String,
) -> system.Effect(Result(Int, String)) {
  use archive <- system.then(traces.load(path))
  use archive <- system.try(archive)
  use written <- system.map(system.write_file(
    output,
    archive.to_string(archive),
  ))
  result.map(written, fn(_) { 0 })
}

/// Export the resulting environment as an input for subsequent agents/programs.
pub fn snapshot(
  path: String,
  output: String,
) -> system.Effect(Result(Int, String)) {
  use archive <- system.then(traces.load(path))
  use archive <- system.try(archive)
  use descriptor <- system.try(descriptor(archive))
  use root <- system.try(
    data.field(descriptor, "output") |> result.try(data.reference),
  )
  use written <- system.map(system.write_file(
    output,
    bundle.to_string(bundle.new(root, archive.store)),
  ))
  result.map(written, fn(_) { 0 })
}
