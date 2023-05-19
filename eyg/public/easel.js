// Main atelier uses rollup from bundle file to bundle file
// other apps use run.js which runs a whole program but assumes it gets the window
// easel is going to be run only in a given element, probably should look like qwik continuations
// lots of work on resumable
import * as Easel from "../build/eyg/easel/embed.mjs";

console.log("starting easel");

// element and node are the same thing when talking about an HTML element
// Text node is not an element
// the closest function exists only on elements
function startIndex(range) {
  const startContainer = range.startContainer;
  const startElement =
    startContainer.nodeType == Node.TEXT_NODE
      ? startContainer.parentElement
      : startContainer;
  let count = 0;
  let e = startElement.previousElementSibling;
  while (e) {
    count += e.textContent.length;
    e = e.previousElementSibling;
  }
  return count + range.startOffset;
}

function handleInput(event, state) {
  // Always at least one range
  // If not zero range collapse to cursor
  const index = startIndex(event.getTargetRanges()[0]);
  if (event.inputType == "insertText") {
    return Easel.insert_text(state, event.data, index);
  }
  if (event.inputType == "insertParagraph") {
    return Easel.insert_paragraph(index, state);
  }
  console.log(index, event);
  return state;
}

// grid of positions from print is not need instead I need to lookup which element has nearest data id and offset
// need my info page for starting position of each element

// exactly the same printing logic OR not using embed for new lines
// if alway looking up before and after

function resume(element) {
  let state = Easel.init();
  let offset = 0;
  onbeforeinput = function (event) {
    [state, offset] = handleInput(event, state);
    console.log(offset);
    element.innerHTML = Easel.html(state);
    let e = element.children[0];
    let countdown = offset;
    while (countdown > e.textContent.length) {
      countdown -= e.textContent.length;
      e = e.nextElementSibling;
    }
    console.log(countdown, offset);
    event.preventDefault();
    setTimeout(() => {
      const selection = window.getSelection();
      selection.removeAllRanges();
      const range = this.document.createRange();
      range.setStart(e, 1);
      selection.addRange(range);
    }, 1);
    return false;
  };
  element.innerHTML = Easel.html(state);
  element.contentEditable = true;
}

function start() {
  const elements = document.querySelectorAll("pre[data-easel]");
  elements.forEach(resume);
}

start();

// document.onselectionchange = function (event) {
//     const selection = document.getSelection();
//     // selection.anchorNode.parentElement.classList.toggle(
//     //   "bg-blue-200"
//     // );
//     console.log(selection, "chan!!");
//   };
//   function foo(event) {

//     const domRange = event.getTargetRanges()[0];
//     console.log(domRange);
//     return false;
//   }
