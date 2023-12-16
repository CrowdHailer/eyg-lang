export function files(event) {
  return Array.from(event.target.files);
}

export function name(file) {
  return file.name;
}

export function mime(file) {
  return file.type;
}

export function text(file) {
  return file.text();
}
