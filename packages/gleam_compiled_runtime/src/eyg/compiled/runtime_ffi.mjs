import { Some, None } from "../../../gleam_stdlib/gleam/option.mjs";
import { Call, Bind, Handle, Perform, Resume, MaskCall, PureCall, ShallowCall, Suspend, Eff } from "./runtime.mjs";
export const step = value =>
  value instanceof Call || value instanceof Bind || value instanceof Handle ||
  value instanceof Perform || value instanceof Resume ||
  value instanceof MaskCall || value instanceof PureCall || value instanceof ShallowCall || value instanceof Suspend
    ? new Some(value) : new None();
export const effect = value => value instanceof Eff ? new Some(value) : new None();
