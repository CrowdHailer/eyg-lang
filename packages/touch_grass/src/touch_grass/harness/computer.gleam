//// The effects available to a program running on a computer.
//// 
//// ## Naming
//// Name "computer" is not great as lots of things are computers.
//// This is the default based on some assumption, so a machine with filesystem etc.
//// Is posix a better name, I've not dived in that deeply and maybe Linux etc is not very Posix.

import gleam/http/request.{type Request}
import touch_grass as tg
import touch_grass/cryptography/create_key
import touch_grass/cryptography/hash
import touch_grass/cryptography/sign
import touch_grass/file_system/append_file
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/interface

/// The case effect requested before any processing.
/// 
/// Does not have an Abort that is a helpful tools that is based on top of Exit in this circumstance.
/// 
/// Should CreateKey end up in an assumption of workspace platform.
pub type Effect {
  AppendFile(append_file.Input)
  CreateKey(create_key.Algorithm)
  Cwd
  DecodeJson(BitArray)
  DeleteFile(path: String)
  Env(name: String)
  EygParse(source: String)
  Fetch(Request(BitArray))
  Hash(hash.Input)
  Now
  Random(Int)
  ReadDirectory(path: String)
  ReadFile(read_file.Input)
  Sign(sign.Request)
  Sleep(Int)
  StandardError(String)
  StandardIn
  StanardOut(String)
  WriteFile(write_file.Input)
}

/// The complete computer harness.
pub fn effects() -> interface.Harness(Effect, meta) {
  [
    // tg.abort() |> tg.map(Abort),
    tg.append_file() |> tg.map(AppendFile),
    tg.create_key() |> tg.map(CreateKey),
    tg.cwd() |> tg.replace(Cwd),
    tg.decode_json() |> tg.map(DecodeJson),
    tg.delete_file() |> tg.map(DeleteFile),
    tg.env() |> tg.map(Env),
    // tg.exit() |> tg.map(Exit),
    tg.eyg_parse() |> tg.map(EygParse),
    tg.fetch() |> tg.map(Fetch),
    // tg.flip() |> tg.replace(Flip),
    tg.hash() |> tg.map(Hash),
    // tg.make_directory() |> tg.map(MakeDirectory),
    tg.now() |> tg.replace(Now),

    // tg.prompt() |> tg.map(Prompt),
    tg.random() |> tg.map(Random),
    tg.read_directory() |> tg.map(ReadDirectory),
    tg.read_file() |> tg.map(ReadFile),
    tg.sign() |> tg.map(Sign),
    tg.sleep() |> tg.map(Sleep),
    tg.standard_error() |> tg.map(StandardError),
    tg.standard_in() |> tg.replace(StandardIn),
    tg.standard_out() |> tg.map(StanardOut),
    tg.write_file() |> tg.map(WriteFile),
  ]
}
