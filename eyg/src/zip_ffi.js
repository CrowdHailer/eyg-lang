import AdmZip from "adm-zip";
// https://www.digitalocean.com/community/tutorials/how-to-work-with-zip-files-in-node-js

export function zip(items) {
  const zip = new AdmZip();
  items.forEach(([file, content]) => {
    zip.addFile(file, content);
  });
  let buffer = zip.toBuffer();
  return buffer;
}
