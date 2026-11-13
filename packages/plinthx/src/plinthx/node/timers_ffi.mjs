import { setTimeout as delay } from "node:timers/promises";
import * as timers from "node:timers";

export const sleep = milliseconds => delay(milliseconds);
export const setTimeout = (milliseconds, callback) => timers.setTimeout(callback, milliseconds);
export const clearTimeout = timeout => timers.clearTimeout(timeout);
