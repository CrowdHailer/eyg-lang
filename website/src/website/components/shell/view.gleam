// This double error handling from evaluated to 
// pub fn run_status(shell) {
//   let Shell(run:, ..) = shell
//   case run.return {
//     Ok(_) -> "Done"
//     Error(#(break.UnhandledEffect(label, lift), meta, env, k)) ->
//       case run.started {
//         True -> "Running"
//         False ->
//           case todo {
//             True -> "Waiting"
//             False -> "Error"
//           }
//       }
//     Error(#(break.UndefinedReference(ref), meta, env, k)) -> todo
//     Error(#(break.UndefinedRelease(ref, _, _), meta, env, k)) -> todo
//     _ -> "Error"
//   }
// }
