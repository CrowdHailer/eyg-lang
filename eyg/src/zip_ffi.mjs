import { BitArray } from "./gleam.mjs";


export async function zipItems(items) {
  const zipFileWriter = new zip.BlobWriter();
  const zipWriter = new zip.ZipWriter(zipFileWriter);

  for (const [file, bitArray] of items) {
    console.log(file, bitArray)
    // Why blob
    // why list when making a blob
    const reader = new zip.BlobReader(new Blob([bitArray.buffer]))
    await zipWriter.add(file, reader);
  }
  await zipWriter.close()
  const blob = await zipFileWriter.getData()
  console.log(blob);
  const done = new BitArray(new Uint8Array(await blob.arrayBuffer()));
  console.log(done);
  return done
}