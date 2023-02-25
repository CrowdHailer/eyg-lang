export function getHash() {
  return decodeURIComponent(window.location.hash.slice(1));
}

export function setHash(hash) {
  history.replaceState(undefined, undefined, "#" + hash);
}

export function startWorker(path) {
  return new Worker(path);
}

export function postMessage(worker, message) {
  worker.postMessage(message);
}

export function onMessage(worker, callback) {
  worker.addEventListener("message", function (msg) {
    console.log("message from worker received in main:", msg);
    callback(msg.data);
  });
}
