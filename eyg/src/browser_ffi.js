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

// https://www.stefanjudis.com/snippets/how-trigger-file-downloads-with-javascript/
export function downloadFile(file) {
  // Create a link and set the URL using `createObjectURL`
  const link = document.createElement("a");
  link.style.display = "none";
  link.href = URL.createObjectURL(file);
  link.download = file.name;

  // It needs to be added to the DOM so it can be clicked
  document.body.appendChild(link);
  link.click();

  // To make this work on Firefox we need to wait
  // a little while before removing it.
  setTimeout(() => {
    URL.revokeObjectURL(link.href);
    link.parentNode.removeChild(link);
  }, 0);
}

