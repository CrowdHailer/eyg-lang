import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/platform
import eyg/cli/system
import gleam/dict
import gleam/http
import gleam/list
import gleam/option.{None}
import gleam/result
import ogre/origin

const eyg_origin: client.Client = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

pub const config: config.Config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)

pub type Sandbox {
  Sandbox(
    stdin: List(String),
    stdout: List(String),
    files: dict.Dict(String, String),
  )
}

pub fn sandbox() -> Sandbox {
  Sandbox(stdin: [], stdout: [], files: dict.new())
}

pub fn with_stdin(sandbox: Sandbox, text: String) -> Sandbox {
  Sandbox(..sandbox, stdin: list.append(sandbox.stdin, [text]))
}

pub fn with_files(sandbox: Sandbox, files: List(#(String, String))) -> Sandbox {
  let files = dict.merge(sandbox.files, dict.from_list(files))
  Sandbox(..sandbox, files:)
}

pub fn with_file(sandbox: Sandbox, path: String, content: String) -> Sandbox {
  with_files(sandbox, [#(path, content)])
}

pub fn run(effect: system.Effect(a), sandbox: Sandbox) -> #(a, Sandbox) {
  case effect {
    system.Done(value) -> #(value, sandbox)
    system.ReadFile(path, resume) -> {
      dict.get(sandbox.files, path)
      |> result.replace_error("missing file")
      |> resume()
      |> run(sandbox)
    }
    system.Stdin(resume) -> {
      let #(response, stdin) = case sandbox.stdin {
        [] -> #(Error(""), [])
        [value, ..rest] -> #(Ok(value), rest)
      }
      let sandbox = Sandbox(..sandbox, stdin:)
      run(resume(response), sandbox)
    }
    system.Stdout(text, resume) -> {
      let stdout = [text, ..sandbox.stdout]
      let sandbox = Sandbox(..sandbox, stdout:)
      run(resume(Nil), sandbox)
    }
  }
}
