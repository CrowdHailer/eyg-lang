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

export function startIndex(range) {
  return elementIndex(range.startContainer) + range.startOffset;
}

export function endIndex(range) {
  return elementIndex(range.endContainer) + range.endOffset;
}

export function handleInput(event, insert_text, insert_paragraph) {
  // Always at least one range
  // If not zero range collapse to cursor
  const range = event.getTargetRanges()[0];
  const start = startIndex(range);
  const end = endIndex(range);
  if (event.inputType == "insertText") {
    return insert_text(event.data, start, end);
  }
  if (event.inputType == "insertParagraph") {
    return insert_paragraph(start);
  }
  if (
    event.inputType == "deleteContentBackward" ||
    event.inputType == "deleteContentForward"
  ) {
    return insert_text("", start, end);
  }
}

export function placeCursor(pre, offset) {
  let e = pre.children[0];
  console.log(pre == document.querySelector("pre"));
  let countdown = offset;
  while (countdown > e.textContent.length) {
    console.log("sdsdsds", e, countdown);
    countdown -= e.textContent.length;
    e = e.nextElementSibling;
  }
  const range = window.getSelection().getRangeAt(0);
  console.log(range, "range", countdown);
  // range needs to be set on the text node
  console.log("dinal", e.firstChild, countdown);
  //   TODO should be countdown
  range.setStart(e.firstChild, 0);
  range.setEnd(e.firstChild, 0);
}
