import { Result$Ok, Result$Error } from "./gleam.mjs";

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
  // pre elements are in some cases focused on and they don't have a value field
  if (input.value != undefined) {
    let type = input.type;
    input.type = 'text';
    input.setSelectionRange(0, input.value.length);
    input.type = type;
  }
}

export function any() {

}

const DB_NAME = "fs-db"
const STORE_NAME ="handles"
const DIR_HANDLE_KEY = 'selected-directory';

export async function show_save_directory_picker() {
  try {
    const dirHandle = await window.showDirectoryPicker();
    await saveDirectoryHandle(dirHandle)
    return Result$Ok(dirHandle);
  } catch (error) {
    return Result$Error(error.toString());
  }
}

export async function get_persisted_directory() {
  try {
    const dirHandle = await loadDirectoryHandle();
    if (!dirHandle) return null;
    
    
    const perm = await dirHandle.requestPermission({ mode: 'readwrite' });
    console.log(perm)
    if (perm === 'granted') {
      return Result$Ok(dirHandle);
    }
    return Result$Error("none linked");
  } catch (error) {
    return Result$Error(error.toString());
  }
}


async function saveDirectoryHandle(dirHandle) {
  const db = await openDB();
  const tx = db.transaction(STORE_NAME, 'readwrite');
  const store = tx.objectStore(STORE_NAME);
  await store.put(dirHandle, DIR_HANDLE_KEY);
  await tx.complete;
}

// Helper to load directory handle from IndexedDB
async function loadDirectoryHandle() {
  try {
    const db = await openDB();
    const tx = db.transaction(STORE_NAME, 'readonly');
    const store = tx.objectStore(STORE_NAME);
    const request = store.get(DIR_HANDLE_KEY);
    
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  } catch (err) {
    console.log("No saved directory handle found");
    return null;
  }
}

// Helper to open/create IndexedDB
function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    
    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
  });
}
