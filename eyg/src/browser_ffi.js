// for atelier_ffi must be top level
const fKey = new RegExp("^F\\d+$");

export function listenKeypress(dispatch) {
  // https://medium.com/analytics-vidhya/implementing-keyboard-controls-or-shortcuts-in-javascript-82e11fccbf0c
  document.addEventListener("keydown", function (event) {
    if (document.activeElement === document.body) {
      if (
        event.altKey ||
        event.ctrlKey ||
        event.metaKey ||
        fKey.test(event.key)
      ) {
        // These should behave normally
        return;
      } else {
        event.preventDefault();
      }
    }
    dispatch(event.key);
  });
}
