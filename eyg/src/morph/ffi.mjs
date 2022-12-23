// TODO move separte to morph transformation
export function listenKeypress(dispatch) {
  // https://medium.com/analytics-vidhya/implementing-keyboard-controls-or-shortcuts-in-javascript-82e11fccbf0c
  document.addEventListener("keydown", function (event) {
    console.log("HWYHYY");
    event.preventDefault()
    dispatch(event.key);
  });
}
// NOTE HERE all in browser ffi
