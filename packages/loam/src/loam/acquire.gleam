//// Fetchers run outside the sandbox. All produce the same verified immutable
//// objects; execution and replay have no Git/HTTP-specific filesystem rules.

import filepath
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/bit_array
import gleam/http/request
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import loam/environment
import loam/git
import loam/sandbox/fs
import loam/system
import simplifile
import touch_grass/acquire as acquisition

pub type Receipt {
  Receipt(source: acquisition.Source, resolved: String, artifact: bundle.Bundle)
}

pub type Fetcher =
  fn(acquisition.Input) -> system.Effect(Result(Receipt, String))

/// Authorities are explicit and separate from HTTP grants. Local repositories
/// require an exact canonical path grant, never access to an entire host tree.
pub fn authority(source: acquisition.Source) -> Result(String, String) {
  case source {
    acquisition.Git("/" <> _ as url, _) -> local_authority(url)
    acquisition.Git(url, _) -> {
      use parsed <- result.try(
        uri.parse(url) |> result.replace_error("invalid repository URL"),
      )
      case
        parsed.scheme,
        parsed.host,
        parsed.userinfo,
        parsed.query,
        parsed.fragment
      {
        Some("file"), host, None, None, None
          if host == None || host == Some("")
        -> {
          use path <- result.try(
            uri.percent_decode(parsed.path)
            |> result.replace_error("invalid file URL encoding"),
          )
          local_authority(path)
        }
        Some("https"), Some(host), None, _, None -> Ok("git:" <> host)
        _, _, _, _, _ ->
          Error("repositories require HTTPS or an absolute local/file URL")
      }
    }
    acquisition.Http(url) -> {
      use parsed <- result.try(
        uri.parse(url) |> result.replace_error("invalid input URL"),
      )
      case parsed.scheme, parsed.host, parsed.userinfo, parsed.fragment {
        Some("http"), Some(host), None, None
        | Some("https"), Some(host), None, None
        -> Ok(host)
        _, _, _, _ ->
          Error(
            "HTTP acquisition requires an HTTP(S) URL without userinfo or fragment",
          )
      }
    }
  }
}

fn local_authority(path) {
  case string.starts_with(path, "/"), filepath.expand(path) {
    True, Ok(path) -> Ok("git:file:" <> path)
    _, _ -> Error("local repositories require an absolute path")
  }
}

/// The trusted acquisition adapter. Called only after the broker authorises a
/// live observation. Scratch state is never mounted into the agent's workspace.
pub fn perform(
  input: acquisition.Input,
) -> system.Effect(Result(Receipt, String)) {
  use _ <- system.try(authority(input.source))
  case input.source {
    acquisition.Http(url) -> {
      use request <- system.try(
        request.to(url) |> result.replace_error("invalid input URL"),
      )
      use artifact <- system.map(http(
        request.set_body(request, <<>>),
        input.expected,
        sha256.hash,
      ))
      result.map(artifact, fn(artifact) { Receipt(input.source, url, artifact) })
    }
    acquisition.Git(url, ref) -> {
      use scratch <- system.then(system.temporary_directory())
      use scratch <- system.try(scratch)
      let checkout = filepath.join(scratch, "repository")
      use receipt <- system.then(repository_receipt(
        url,
        ref,
        checkout,
        input.expected,
        sha256.hash,
      ))
      use cleaned <- system.map(system.delete_file(scratch))
      let receipt = case cleaned {
        Ok(_) -> receipt
        Error(reason) ->
          Error(
            "could not clean acquisition scratch directory: "
            <> simplifile.describe_error(reason),
          )
      }
      result.map_error(receipt, string.replace(_, scratch, "<acquisition>"))
    }
  }
}

pub type Budget {
  Budget(bytes: Int, entries: Int)
}

pub fn budget() -> Budget {
  Budget(64_000_000, 10_000)
}

/// Capture an explicitly selected directory. Unsupported entries (including
/// symlinks) fail instead of silently depending on something outside the tree.
pub fn local(
  path: String,
  ignore: List(String),
  sha256: store.Sha256,
) -> system.Effect(Result(bundle.Bundle, String)) {
  use result <- system.map(read(path, ignore, budget(), 0))
  use #(tree, _) <- result.map(result)
  let #(blocks, root) = environment.store_tree(tree, store.new(), sha256)
  bundle.new(root, blocks)
}

fn read(path, ignore, budget: Budget, depth) {
  use Nil <- system.try(case budget.entries <= 0 || depth > 128 {
    True -> Error("input tree entry limit exceeded")
    False -> Ok(Nil)
  })
  use info <- system.then(system.file_info(path))
  use system.Metadata(kind, size) <- system.try(result.map_error(
    info,
    simplifile.describe_error,
  ))
  let budget = Budget(..budget, entries: budget.entries - 1)
  case kind {
    simplifile.File -> {
      use Nil <- system.try(case size > budget.bytes {
        True -> Error("input tree byte limit exceeded")
        False -> Ok(Nil)
      })
      use contents <- system.then(system.read_file_range(path, 0, size + 1))
      use contents <- system.try(result.map_error(
        contents,
        simplifile.describe_error,
      ))
      use Nil <- system.try(case bit_array.byte_size(contents) == size {
        True -> Ok(Nil)
        False -> Error("file changed while acquiring: " <> path)
      })
      let assert fs.File(permissions:, ..) = fs.file("")
      system.Done(
        Ok(#(
          fs.File(contents, permissions),
          Budget(..budget, bytes: budget.bytes - size),
        )),
      )
    }
    simplifile.Directory -> {
      use names <- system.then(system.read_directory(path))
      use names <- system.try(result.map_error(names, simplifile.describe_error))
      use children <- system.map(
        system.fold(names, Ok(#([], budget)), fn(acc, name) {
          use #(children, budget) <- system.try(acc)
          case list.contains(ignore, name) {
            True -> system.Done(Ok(#(children, budget)))
            False -> {
              use child <- system.map(read(
                filepath.join(path, name),
                ignore,
                budget,
                depth + 1,
              ))
              use #(child, budget) <- result.map(child)
              #([#(name, child), ..children], budget)
            }
          }
        }),
      )
      use #(children, budget) <- result.map(children)
      #(fs.directory(children), budget)
    }
    _ -> system.Done(Error("unsupported input entry: " <> path))
  }
}

/// With no expected CID this is acquisition/locking, not a reproducible fetch.
/// Retain the returned bundle and use its root for subsequent acquisitions.
pub fn http(
  request: request.Request(BitArray),
  expected: Option(String),
  sha256: store.Sha256,
) -> system.Effect(Result(bundle.Bundle, String)) {
  use response <- system.then(system.fetch(request))
  use response <- system.try(result.replace_error(
    response,
    "input fetch failed",
  ))
  use Nil <- system.try(
    case
      response.status >= 200
      && response.status < 300
      && bit_array.byte_size(response.body) <= budget().bytes
    {
      True -> Ok(Nil)
      False -> Error("input fetch failed or exceeded byte limit")
    },
  )
  let #(blocks, root) = store.put_binary(store.new(), response.body, sha256)
  system.Done(verify(bundle.new(root, blocks), expected))
}

/// The caller supplies an unused temporary checkout path. Git is an acquisition
/// tool only: the result contains files, never a mutable checkout dependency.
pub fn repository(
  url: String,
  revision: String,
  checkout: String,
  expected: Option(String),
  sha256: store.Sha256,
) -> system.Effect(Result(bundle.Bundle, String)) {
  use existing <- system.then(system.file_info(checkout))
  use Nil <- system.try(case existing {
    Error(simplifile.Enoent) -> Ok(Nil)
    _ -> Error("scratch checkout must not exist")
  })
  use receipt <- system.then(repository_receipt(
    url,
    Some(revision),
    checkout,
    expected,
    sha256,
  ))
  use _ <- system.then(system.delete_file(checkout))
  system.Done(result.map(receipt, fn(receipt) { receipt.artifact }))
}

fn repository_receipt(url, ref, checkout, expected, sha256) {
  use cloned <- system.then(git.snapshot(url, ref, checkout))
  use commit <- system.try(cloned)
  use entries <- system.then(system.command(
    "git",
    ["-C", checkout, "ls-files", "--stage"],
    checkout,
  ))
  use entries <- system.try(result.replace_error(
    entries,
    "could not inspect repository entries",
  ))
  use Nil <- system.try(
    case
      string.split(entries, "\n") |> list.any(string.starts_with(_, "160000 "))
    {
      True -> Error("submodules must be acquired separately")
      False -> Ok(Nil)
    },
  )
  use acquired <- system.then(local(checkout, [".git"], sha256))
  system.Done(
    acquired
    |> result.try(verify(_, expected))
    |> result.map(fn(artifact) {
      Receipt(acquisition.Git(url, ref), commit, artifact)
    }),
  )
}

pub fn verify(
  bundle: bundle.Bundle,
  expected: Option(String),
) -> Result(bundle.Bundle, String) {
  case expected {
    Some(root) if root != bundle.root ->
      Error("fetched input does not match its locked content identity")
    _ -> Ok(bundle)
  }
}
