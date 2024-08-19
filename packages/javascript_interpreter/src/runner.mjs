import { eval_, Effect } from "./interpreter.mjs";

export async function exec(source, extrinsic) {
  let state = eval_(source)
  while (true) {
    if (state.break === undefined) return state.control
    switch (state.break.constructor) {
      case Effect:
        let { label, lift } = state.break;
        let handle = extrinsic[label]
        if (handle === undefined) throw new Error("unhandled effect")
        state.resume(await handle(lift))

        break;
      default:
        throw state.break
    }
  }
}

