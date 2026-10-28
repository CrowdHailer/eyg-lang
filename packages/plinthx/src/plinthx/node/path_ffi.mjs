import { resolve as nativeResolve } from "node:path";
export const resolve = paths => nativeResolve(...paths);
