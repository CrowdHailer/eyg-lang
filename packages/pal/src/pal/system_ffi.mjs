import { Result$Ok, Result$Error } from "../gleam.mjs";

export function href(location) {
  try {
    return Result$Ok(location.href);
  } catch (error) {
    return Result$Error(`${error}`);
  }
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

export async function show_save_directory_picker() {
  try {
    const dirHandle = await window.showDirectoryPicker();
    await saveDirectoryHandle(dirHandle)
    return Result$Ok(dirHandle);
  } catch (error) {
    return Result$Error(error.toString());
  }
}
