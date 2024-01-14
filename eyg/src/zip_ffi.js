import AdmZip from "adm-zip";
// https://www.digitalocean.com/community/tutorials/how-to-work-with-zip-files-in-node-js

export function zip(items) {
  const zip = new AdmZip();
  items.forEach(([file, bitArray]) => {
    zip.addFile(file, bitArray.buffer);
  });
  let buffer = zip.toBuffer();
  return buffer;
}
