// Main atelier uses rollup from bundle file to bundle file
// other apps use run.js which runs a whole program but assumes it gets the window
// easel is going to be run only in a given element, probably should look like qwik continuations
// lots of work on resumable
// The server from the eyg project moved the build directory
import * as Easel from "../build/dev/javascript/eyg/easel/embed.mjs";
import * as Experiment from "../build/dev/javascript/eyg/experiment.mjs";
// Some stateful error with rollup happening here
// import * as db2 from "./db/index.js";
// console.log(db2);
// let db = { hello: db2.hello };
// console.log("yeeeee");
// Object.assign(db, db2);

Experiment.run();

console.log("starting easel");

// element and node are the same thing when talking about an HTML element
// Text node is not an element
// the closest function exists only on elements
function elementIndex(node) {
  const startElement =
    node.nodeType == Node.TEXT_NODE ? node.parentElement : node;
  let count = 0;
  let e = startElement.previousElementSibling;
  while (e) {
    count += e.textContent.length;
    e = e.previousElementSibling;
  }
  return count;
}

function startIndex(range) {
  return elementIndex(range.startContainer) + range.startOffset;
}

function endIndex(range) {
  return elementIndex(range.endContainer) + range.endOffset;
}

function handleInput(event, state) {
  // Always at least one range
  // If not zero range collapse to cursor
  const range = event.getTargetRanges()[0];
  const start = startIndex(range);
  const end = endIndex(range);
  if (event.inputType == "insertText") {
    return Easel.insert_text(state, event.data, start, end);
  }
  if (event.inputType == "insertParagraph") {
    return Easel.insert_paragraph(start, state);
  }
  if (
    event.inputType == "deleteContentBackward" ||
    event.inputType == "deleteContentForward"
  ) {
    return Easel.insert_text(state, "", start, end);
  }
  console.log(start, event);
  return state;
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
        const start = startIndex(range);
        updateElement(element, state, start);
      }
      if (event.ctrlKey && event.key == "f") {
        event.preventDefault();
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const start = startIndex(range);
        const end = endIndex(range);
        [state, offset] = Easel.insert_function(state, start, end);
        updateElement(element, state, offset);
        return false;
      }
      if (event.ctrlKey && event.key == "j") {
        event.preventDefault();
        event.stopPropagation();
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const start = startIndex(range);
        const end = endIndex(range);
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
    const start = startIndex(range);
    const end = endIndex(range);
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
  let e = element.children[0];
  let countdown = offset;
  while (countdown > e.textContent.length) {
    countdown -= e.textContent.length;
    e = e.nextElementSibling;
  }
  const range = window.getSelection().getRangeAt(0);
  // range needs to be set on the text node
  range.setStart(e.firstChild, countdown);
  range.setEnd(e.firstChild, countdown);
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
      return;
    }
    states[index](range);
  };

  const loaders = Array.prototype.slice.call(
    document.querySelectorAll('button[data-action="load"]')
  );
  loaders.map(startLoader);
}

start();

// full page routing for selection change reference with ID
// put more in plinth
// options list of enum/go fn types or all the options fixed.
function startLoader(button) {
  console.log(button);
  button.onclick = async function (event) {
    // chrome only
    // firefox support is for originprivatefilesystem and drag and drop blobs
    // show dir for db of stuff only
    // const [dir] = await window.showDirectoryPicker();
    // console.log(dir);
    const [fileHandle] = await window.showOpenFilePicker();
    const file = await fileHandle.getFile();
    // .json not available
    const json = JSON.parse(await file.text());
    const writableStream = await fileHandle.createWritable();
    const data = new Blob([JSON.stringify({ foo: 2 }, null, 2)], {
      type: "application/json",
    });
    await writableStream.write(data);
    let state = Easel.init(json);
    let offset = 0;
    // button is the button
    const pre = button.parentElement;
    pre.contentEditable = true;
    pre.innerHTML = Easel.html(state);

    pre.onbeforeinput = function (event) {
      console.log(event);
      [state, offset] = handleInput(event, state);
      updateElement(pre, state, offset);
      return false;
    };
    pre.onkeydown = function (event) {
      if (event.key == "Escape") {
        state = Easel.escape(state);
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        const start = startIndex(range);
        updateElement(pre, state, start);
      }
    };
  };
}
