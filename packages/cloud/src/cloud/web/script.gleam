//// The page script that connects the browser to the terminal.
////
//// A server component cannot decide per key whether to prevent the
//// browser's default, so this script decides in the browser. Keys on an
//// element marked `data-eyg-keys` are sent as `eyg-key` events and their
//// default prevented, except browser shortcuts with Ctrl or Meta, which keep
//// working (copy, paste, reload). Ctrl+A, E, U and K are text editing keys
//// and are sent. Pasted text is sent as an `eyg-paste` event.

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

"
