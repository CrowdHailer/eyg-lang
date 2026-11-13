//// Fork a sealed environment. Local operations use the same sandbox as the
//// original; all external requests share one ordered observation protocol.

import eyg/cli/internal/config
import eyg/cli/internal/traces
import eyg/cli/sandbox
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import filepath
import glasshouse/bundle
import glasshouse/cohort
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import loam/broker
import loam/environment
import loam/execute
import loam/source
import loam/system
import loam/virtual

pub type Variant {
  Variant(
    name: String,
    files: List(#(String, String)),
    prompts: Option(List(String)),
  )
}

pub type Plan {
  Plan(hosts: List(String), variants: List(Variant))
}

pub fn execute(
  path: String,
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use baseline <- system.then(traces.load(path))
  use baseline <- system.try(baseline)
  use #(environment, observations) <- system.try(sandbox.inputs(baseline))
  use #(entry, kind) <- system.try(sandbox.entry(baseline))
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use plan <- system.then(read_plan(input, cwd, config))
  use plan <- system.try(plan)
  let names = list.map(plan.variants, fn(variant) { slug(variant.name) })
  use Nil <- system.try(
    case list.length(names) == list.length(list.unique(names)) {
      True -> Ok(Nil)
      False -> Error("variant names must have distinct filename forms")
    },
  )
  let directory = filepath.directory_name(path)
  use results <- system.then(
    system.traverse(plan.variants, fn(variant) {
      use input <- system.try(reproduction(environment, variant))
      let prompts = option.unwrap(variant.prompts, sandbox.prompts(baseline))
      let id = baseline.session.id <> "-" <> slug(variant.name)
      use archive <- system.then(sandbox.run(
        input,
        entry,
        kind,
        prompts,
        broker.Fork(observations, plan.hosts),
        id,
        config,
      ))
      use archive <- system.try(archive)
      use saved <- system.map(traces.save_shared(archive, directory))
      use _ <- result.map(saved)
      sandbox.summarize(variant.name, archive)
    }),
  )
  use results <- system.try(result.all(results))
  let summaries = [sandbox.summarize("recorded", baseline), ..results]
  let report_path =
    filepath.join(directory, baseline.session.id <> ".cohort.json")
  use written <- system.then(system.write_file(
    report_path,
    json.to_string(cohort.report_encode(baseline.session.id, summaries)),
  ))
  use Nil <- system.try(written)
  use Nil <- system.map(
    system.stdout(cohort.table(summaries, baseline.session.cwd)),
  )
  Ok(0)
}

pub fn reproduction(
  input: bundle.Bundle,
  variant: Variant,
) -> Result(bundle.Bundle, String) {
  use environment <- result.try(environment.open(input))
  let machine = virtual.fork(environment)
  use machine <- result.map(
    list.try_fold(variant.files, machine, fn(machine, file) {
      use path <- result.map(
        system.resolve_relative(environment.cwd, file.0)
        |> result.replace_error("invalid variant path"),
      )
      virtual.with_file(machine, path, virtual.Present(<<file.1:utf8>>))
    }),
  )
  environment.seal(
    environment.Environment(..environment, files: machine.file_system),
    traces.sha256,
  )
}

fn read_plan(
  input: source.Input,
  cwd: String,
  config: config.Config,
) -> system.Effect(Result(Plan, String)) {
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))
  let state = config.state(config)
  use #(result, _) <- system.map(execute.pure_loop(
    expression.execute(source, []),
    state,
  ))
  case result {
    Ok(value) -> decode_plan(value) |> result.map_error(simple_debug.describe)
    Error(#(reason, location, _, k)) ->
      Error(execute.render_error(reason, location, k, cwd))
  }
}

pub fn decode_plan(value: execute.Value) -> Result(Plan, execute.Reason) {
  use hosts <- result.try(cast.field(
    "hosts",
    cast.as_list_of(_, cast.as_string),
    value,
  ))
  use variants <- result.map(cast.field(
    "variants",
    cast.as_list_of(_, decode_variant),
    value,
  ))
  Plan(hosts, variants)
}

fn decode_variant(value) {
  use name <- result.try(cast.field("name", cast.as_string, value))
  use files <- result.try(cast.field(
    "files",
    cast.as_list_of(_, fn(file) {
      use path <- result.try(cast.field("path", cast.as_string, file))
      use contents <- result.map(cast.field("contents", cast.as_string, file))
      #(path, contents)
    }),
    value,
  ))
  use prompts <- result.map(cast.field(
    "prompts",
    cast.as_option(_, cast.as_list_of(_, cast.as_string)),
    value,
  ))
  Variant(name, files, prompts)
}

fn slug(name: String) -> String {
  name
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(c) {
    case string.contains("abcdefghijklmnopqrstuvwxyz0123456789", c) {
      True -> c
      False -> "-"
    }
  })
  |> string.concat
}
