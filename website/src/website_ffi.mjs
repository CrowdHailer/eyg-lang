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

// https://stackoverflow.com/questions/33406169/failed-to-execute-setselectionrange-on-htmlinputelement-the-input-elements
export function selectAllInput(input) {
  let type = input.type;
  input.type = 'text';
  input.setSelectionRange(0, input.value.length);
  input.type = type;
}