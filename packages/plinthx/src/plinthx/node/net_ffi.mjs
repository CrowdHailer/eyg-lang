import net from "node:net";
import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function connectUnix(path) {
  return new Promise(resolve => {
    const socket = net.createConnection({path});
    socket.setEncoding("utf8");
    socket.once("connect", () => resolve(Result$Ok(socket)));
    socket.once("error", error => resolve(Result$Error(String(error))));
  });
}
export const onData = (socket, callback) => { socket.on("data", callback); };
export const onError = (socket, callback) => { socket.on("error", error => callback(String(error))); };
export function write(socket, text) {
  try { socket.write(text); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export const close = socket => { socket.destroy(); };
