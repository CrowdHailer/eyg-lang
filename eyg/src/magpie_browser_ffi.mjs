export function setHash(hash) {
  history.replaceState(undefined, undefined, "#" + hash);
}
