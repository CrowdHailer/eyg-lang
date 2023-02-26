import { infer } from "./atelier/worker.mjs";
// build as es
self.onmessage = function (msg) {
  console.log("received msg: ", msg);
  self.postMessage(infer(msg.data));
};
