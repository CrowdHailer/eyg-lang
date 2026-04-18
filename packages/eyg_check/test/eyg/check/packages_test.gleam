import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/platform
import eyg/interpreter/simple_debug
import eyg/ir/dag_json
import eyg/parser
import filepath
import gleam/http
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None}
import ogre/origin
import simplifile

const eyg_origin = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

const config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)

fn packages_dir() {
  let assert Ok(cwd) = simplifile.current_directory()
  let assert Ok(path) = filepath.expand(cwd <> "/../../eyg_packages")
  path
}

const index_json = "index.eyg.json"

const index = "index.eyg"

const test_eyg = "test.eyg"

// TODO reinstate with package lookup
const filtered = ["catfact", "spotless"]

pub fn packages_test() {
  let assert Ok(packages) = simplifile.read_directory(packages_dir())
  let packages = list.filter(packages, fn(p) { !list.contains(filtered, p) })
  promise.await_list(list.map(packages, check_package))
}

fn check_package(package) {
  let dir = packages_dir() <> "/" <> package
  io.println("checking package " <> package)
  let assert Ok(entries) = simplifile.read_directory(dir)
  use _ <- promise.await(case list.contains(entries, index_json) {
    True -> check_index_json(package)
    False -> promise.resolve(Nil)
  })
  use _ <- promise.await(case list.contains(entries, index) {
    True -> check_index(package)
    False -> promise.resolve(Nil)
  })
  use _ <- promise.await(case list.contains(entries, test_eyg) {
    True -> check_test(package)
    False -> promise.resolve(Nil)
  })
  promise.resolve(Nil)
}

fn check_index_json(package) {
  let dir = packages_dir() <> "/" <> package
  let index_path = dir <> "/" <> index_json
  let assert Ok(code) = simplifile.read(index_path)
  let assert Ok(source) = json.parse(code, dag_json.decoder(Nil))
  use return <- promise.await(execute.pure(source, dir, eyg_origin))
  case return {
    Ok(_) -> {
      io.println("index.eyg.json Ok for " <> package)
      promise.resolve(Nil)
    }
    Error(reason) -> {
      panic as { simple_debug.describe(reason) <> " in " <> package }
    }
  }
}

fn check_index(package) {
  let dir = packages_dir() <> "/" <> package
  let index_path = dir <> "/" <> index
  let assert Ok(code) = simplifile.read(index_path)
  let assert Ok(source) = parser.all_from_string(code)

  use return <- promise.await(execute.pure(source, dir, eyg_origin))
  case return {
    Ok(_) -> {
      io.println("index.eyg Ok for " <> package)
      promise.resolve(Nil)
    }
    Error(reason) -> {
      panic as { simple_debug.describe(reason) <> " in " <> package }
    }
  }
}

fn check_test(package) {
  let dir = packages_dir() <> "/" <> package
  let test_path = dir <> "/" <> test_eyg
  let assert Ok(code) = simplifile.read(test_path)
  let assert Ok(source) = parser.all_from_string(code)

  use return <- promise.await(execute.block(source, [], dir, config))
  case return {
    Ok(_) -> {
      io.println("test.eyg Ok for " <> package)
      promise.resolve(Nil)
    }
    Error(reason) -> {
      panic as { simple_debug.describe(reason) <> " in " <> package }
    }
  }
}
