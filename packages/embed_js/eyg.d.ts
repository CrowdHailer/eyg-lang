/** A type in the effect description language. */
export type Type =
  | "integer"
  | "string"
  | "boolean"
  | "unit"
  | { list: Type }
  | { record: Record<string, Type> }
  | { union: Record<string, Type> }
  | { result: { ok: Type; error: Type } };

/**
 * An EYG value as JavaScript. Integers are numbers, lists arrays, records
 * objects, `True({})` and `False({})` booleans, other tags `{$: "Ok", value}`.
 */
export type Value =
  | number
  | string
  | boolean
  | Value[]
  | { $: string; value?: Value }
  | { [field: string]: Value };

/** Effects a program may perform, with the type each lifts out and lowers back. */
export type Effects = Record<string, { lift: Type; lower: Type }>;

/** A function for each effect. Replies are checked against the declared type. */
export type Handlers = Record<string, (input: any) => Value | void>;
export type AsyncHandlers = Record<string, (input: any) => Value | void | Promise<Value | void>>;

export interface Run {
  /** The value of the last expression, when it can be JSON. */
  value?: Value;
  /** The value of the last expression, as EYG prints it. */
  display?: string;
  /** Why the code did not parse, type check or finish. */
  error?: string;
}

export interface Shell {
  /** A string field of a module in scope, its readme by default. */
  text(module: string, field?: string): string;
  /** Check and run code; rejected while another run is pending. Bindings persist. */
  run(code: string, handlers: Handlers): Run;
  /** Load packages, check and run. Overlapping calls are queued in call order. */
  runAsync(code: string, handlers: AsyncHandlers): Promise<Run>;
}

export function createShell(options: {
  effects: Effects;
  /** Origin of an EYG hub for package references, such as "https://eyg.run". */
  hub?: string;
  /** Modules to put in scope by name, given as source. */
  modules?: Record<string, string>;
}): Promise<Shell>;
