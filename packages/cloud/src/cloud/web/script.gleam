//// The page script that connects the browser to the terminal.
////
//// A server component cannot decide per key whether to prevent the
//// browser's default, so this script decides in the browser. Keys on an
//// element marked `data-eyg-keys` are sent as `eyg-key` events and their
//// default prevented, except browser shortcuts with Ctrl or Meta, which keep
//// working (copy, paste, reload). Ctrl+A, E, U and K are text editing keys
//// and are sent. Pasted text is sent as an `eyg-paste` event.
////
//// Files dropped on the terminal, or chosen with an input marked
//// `data-eyg-mount`, are uploaded to `/uploads` with their relative paths.
//// The upload's CID is sent as an `eyg-drop` event.

pub const script =
  "
const terminal = (event) => {
  const element = event.composedPath()[0];
  return element instanceof Element && element.closest('[data-eyg-keys]');
};
const editing = ['a', 'e', 'u', 'k'];
document.addEventListener('keydown', (event) => {
  const element = terminal(event);
  if (!element || event.isComposing) return;
  if (['Shift', 'Control', 'Alt', 'Meta', 'CapsLock'].includes(event.key)) return;
  if (/^F[0-9]+$/.test(event.key)) return;
  if (event.metaKey) return;
  if (event.ctrlKey && !editing.includes(event.key.toLowerCase())) return;
  event.preventDefault();
  element.dispatchEvent(new CustomEvent('eyg-key', {
    detail: { key: event.key, ctrl: event.ctrlKey, alt: event.altKey, shift: event.shiftKey },
  }));
});
document.addEventListener('paste', (event) => {
  const element = terminal(event);
  if (!element) return;
  event.preventDefault();
  const text = event.clipboardData.getData('text/plain');
  element.dispatchEvent(new CustomEvent('eyg-paste', { detail: text }));
});

// Files from a drop, with paths relative to what was dropped.
const entryFiles = async (entry) => {
  if (entry.isFile) {
    const file = await new Promise((resolve, reject) => entry.file(resolve, reject));
    return [{ path: entry.fullPath.replace(/^\\//, ''), file }];
  }
  const reader = entry.createReader();
  const entries = [];
  for (;;) {
    const batch = await new Promise((resolve, reject) => reader.readEntries(resolve, reject));
    if (batch.length === 0) break;
    entries.push(...batch);
  }
  const nested = await Promise.all(entries.map(entryFiles));
  return nested.flat();
};
const droppedFiles = async (transfer) => {
  const entries = [...transfer.items]
    .map((item) => item.webkitGetAsEntry && item.webkitGetAsEntry())
    .filter(Boolean);
  if (entries.length > 0) return (await Promise.all(entries.map(entryFiles))).flat();
  return [...transfer.files].map((file) => ({ path: file.webkitRelativePath || file.name, file }));
};
const upload = async (element, files) => {
  if (files.length === 0) return;
  element.classList.add('uploading');
  try {
    const body = new FormData();
    for (const { path, file } of files) {
      body.append('path', path);
      body.append('file', file);
    }
    const response = await fetch('/uploads', { method: 'POST', body });
    const result = await response.json();
    if (result.upload) {
      element.dispatchEvent(new CustomEvent('eyg-drop', { detail: { upload: result.upload } }));
    }
  } finally {
    element.classList.remove('uploading');
  }
};
document.addEventListener('dragover', (event) => {
  const element = terminal(event);
  if (!element) return;
  event.preventDefault();
  element.classList.add('dropping');
});
document.addEventListener('dragleave', (event) => {
  const element = terminal(event);
  if (element && !element.contains(event.relatedTarget)) element.classList.remove('dropping');
});
document.addEventListener('drop', async (event) => {
  const element = terminal(event);
  if (!element) return;
  event.preventDefault();
  element.classList.remove('dropping');
  upload(element, await droppedFiles(event.dataTransfer));
});
document.addEventListener('input', (event) => {
  const input = event.composedPath()[0];
  if (!(input instanceof HTMLInputElement) || !input.hasAttribute('data-eyg-mount')) return;
  const element = input.closest('.terminal')?.querySelector('[data-eyg-keys]');
  const files = [...input.files].map((file) => ({ path: file.webkitRelativePath || file.name, file }));
  input.value = '';
  if (element) {
    upload(element, files);
    element.focus();
  }
});
"
