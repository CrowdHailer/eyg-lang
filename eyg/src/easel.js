// other apps use run.js which runs a whole program but assumes it gets the window
// easel is going to be run only in a given element, probably should look like qwik continuations
// lots of work on resumable
// The server from the eyg project moved the build directory
import * as Easel from "./easel/embed.mjs";
import * as Loader from "./easel/loader.mjs";
import * as ffi from "./easel_ffi.js";

console.log("starting easel");
function handleInput(event, state) {
  return (
    ffi.handleInput(
      event,
      function (data, start, end) {
        return Easel.insert_text(state, data, start, end);
      },
      function (start) {
        Easel.insert_paragraph(start, state);
      }
    ) || state
  );
}

// grid of positions from print is not need instead I need to lookup which element has nearest data id and offset
// need my info page for starting position of each element

// exactly the same printing logic OR not using embed for new lines
// if alway looking up before and after

async function resume(element) {
  // not really a hash at this point just some key
  const hash = element.dataset.easel.slice(1);
  let response = await fetch("/db/" + hash + ".json");
  let json = await response.json();
  let state = Easel.init(json);
  let offset = 0;
  element.onclick = function () {
    element.onbeforeinput = function (event) {
      event.preventDefault();
      [state, offset] = handleInput(event, state);
      updateElement(element, state, offset);
      return false;
    };
    element.onkeydown = function (event) {
      if (event.key == "Escape") {
        state = Easel.escape(state);
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const start = ffi.startIndex(range);
        updateElement(element, state, start);
      }
      if (event.ctrlKey && event.key == "f") {
        event.preventDefault();
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const start = ffi.startIndex(range);
        const end = ffi.endIndex(range);
        [state, offset] = Easel.insert_function(state, start, end);
        updateElement(element, state, offset);
        return false;
      }
      if (event.ctrlKey && event.key == "j") {
        event.preventDefault();
        event.stopPropagation();
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const start = ffi.startIndex(range);
        const end = ffi.endIndex(range);
        [state, offset] = Easel.call_with(state, start, end);
        updateElement(element, state, offset);
        return false;
      }
      console.log(event);
    };
    element.onblur = function (event) {
      // element.nextElementSibling.classList.add("hidden");
      state = Easel.blur(state);
      updateElement(element, state);
    };
    element.onfocus = function (event) {
      // element.nextElementSibling.classList.remove("hidden");
    };
    element.onclick = undefined;
    // Separate editor i.e. panel from pallet in ide/workshop
    element.nextElementSibling.innerHTML = Easel.pallet(state);
  };
  // maybe on focus should trigger setup
  // maybe embed state should always be rehydrated but the click to edit is a part of that state
  element.innerHTML = Easel.html(state);
  element.contentEditable = true;
  return function (range) {
    const start = ffi.startIndex(range);
    const end = ffi.endIndex(range);
    // console.log("handle selection change", start, end);
    state = Easel.update_selection(state, start, end);
    element.nextElementSibling.innerHTML = Easel.pallet(state);
  };
}

function updateElement(element, state, offset) {
  element.innerHTML = Easel.html(state);
  element.nextElementSibling.innerHTML = Easel.pallet(state);
  if (offset == undefined) {
    return;
  }
  ffi.placeCursor(element, offset);
}

async function start() {
  // doesn't work for type module
  // can have a #hash to run or a data-entry for an if statement
  // console.log(document.currentScript);
  // https://gomakethings.com/converting-a-nodelist-to-an-array-with-vanilla-javascript/
  const elements = Array.prototype.slice.call(
    document.querySelectorAll("pre[data-easel]")
  );
  const states = await Promise.all(elements.map(resume));
  // https://javascript.info/selection-range#selection-events
  // only on document level
  document.onselectionchange = function (event) {
    const selection = window.getSelection();
    const range = selection.getRangeAt(0);
    const container = range.startContainer;
    const element = (
      container.closest ? container : container.parentElement
    ).closest("pre[data-easel]");
    // adding after the fact i.e. in response to a load button gets them out of order
    //
    // console.log(element, );
    const index = elements.indexOf(element);
    if (index < 0) {
      if (window.globalSelectionHandler) {
        window.globalSelectionHandler(range);
      }
      return;
    }
    states[index](range);
  };
}

start();

// -------------------------
// file write
// const writableStream = await fileHandle.createWritable();
// const data = new Blob([JSON.stringify({ foo: 2 }, null, 2)], {
//   type: "application/json",
// });
// await writableStream.write(data);
// --------------

//     let state = Easel.init(json);
//     let offset = 0;
//     // button is the button

//     pre.onkeydown = function (event) {
//       if (event.key == "Escape") {
//         state = Easel.escape(state);
//         const selection = window.getSelection();
//         const range = selection.getRangeAt(0);
//         const start = ffi.startIndex(range);
//         updateElement(pre, state, start);
//       }
//     };
//   };
// }

Loader.run();
