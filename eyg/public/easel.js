// Main atelier uses rollup from bundle file to bundle file
// other apps use run.js which runs a whole program but assumes it gets the window
// easel is going to be run only in a given element, probably should look like qwik continuations
// lots of work on resumable
import * as Easel from "../build/eyg/easel/embed.mjs";

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

function resume(element) {
  let state = Easel.init();
  let offset = 0;
  element.onbeforeinput = function (event) {
    event.preventDefault();
    [state, offset] = handleInput(event, state);
    updateElement(element, state, offset);
    return false;
  };
  element.onkeydown = function (event) {
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
    // console.log(event);
  };
  element.innerHTML = Easel.html(state);
  element.contentEditable = true;
}

function updateElement(element, state, offset) {
  element.innerHTML = Easel.html(state);
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

function start() {
  const elements = document.querySelectorAll("pre[data-easel]");
  elements.forEach(resume);
}

start();
