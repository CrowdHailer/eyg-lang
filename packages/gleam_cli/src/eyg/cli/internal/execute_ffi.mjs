import fs from 'node:fs';
import { Result$Ok, Result$Error, BitArray$BitArray } from "../../../gleam.mjs";
import * as $simplifile from "../../../../simplifile/simplifile.mjs";

export function readAtOffset(path, offset, limit) {
  try {
    const fd = fs.openSync(path, 'r');

    try {
      const buffer = Buffer.alloc(limit);
      // 0 is the buffer offset
      const bytesRead = fs.readSync(fd, buffer, 0, limit, offset);
      return Result$Ok(BitArray$BitArray(buffer.subarray(0, bytesRead)));
    } finally {
      fs.closeSync(fd);
    }
  } catch (error) {
    return Result$Error(cast_error(error.code));
  }
}

// copied from simplifile
// Can be removed if a read_bytes_range function is added to simplifile
function cast_error(error_code) {
  switch (error_code) {
    case "EACCES":
      return new $simplifile.Eacces();
    case "EAGAIN":
      return new $simplifile.Eagain();
    case "EBADF":
      return new $simplifile.Ebadf();
    case "EBADMSG":
      return new $simplifile.Ebadmsg();
    case "EBUSY":
      return new $simplifile.Ebusy();
    case "EDEADLK":
      return new $simplifile.Edeadlk();
    case "EDEADLOCK":
      return new $simplifile.Edeadlock();
    case "EDQUOT":
      return new $simplifile.Edquot();
    case "EEXIST":
      return new $simplifile.Eexist();
    case "EFAULT":
      return new $simplifile.Efault();
    case "EFBIG":
      return new $simplifile.Efbig();
    case "EFTYPE":
      return new $simplifile.Eftype();
    case "EINTR":
      return new $simplifile.Eintr();
    case "EINVAL":
      return new $simplifile.Einval();
    case "EIO":
      return new $simplifile.Eio();
    case "EISDIR":
      return new $simplifile.Eisdir();
    case "ELOOP":
      return new $simplifile.Eloop();
    case "EMFILE":
      return new $simplifile.Emfile();
    case "EMLINK":
      return new $simplifile.Emlink();
    case "EMULTIHOP":
      return new $simplifile.Emultihop();
    case "ENAMETOOLONG":
      return new $simplifile.Enametoolong();
    case "ENFILE":
      return new $simplifile.Enfile();
    case "ENOBUFS":
      return new $simplifile.Enobufs();
    case "ENODEV":
      return new $simplifile.Enodev();
    case "ENOLCK":
      return new $simplifile.Enolck();
    case "ENOLINK":
      return new $simplifile.Enolink();
    case "ENOENT":
      return new $simplifile.Enoent();
    case "ENOMEM":
      return new $simplifile.Enomem();
    case "ENOSPC":
      return new $simplifile.Enospc();
    case "ENOSR":
      return new $simplifile.Enosr();
    case "ENOSTR":
      return new $simplifile.Enostr();
    case "ENOSYS":
      return new $simplifile.Enosys();
    case "ENOBLK":
      return new $simplifile.Enotblk();
    case "ENOTDIR":
      return new $simplifile.Enotdir();
    case "ENOTSUP":
      return new $simplifile.Enotsup();
    case "ENXIO":
      return new $simplifile.Enxio();
    case "EOPNOTSUPP":
      return new $simplifile.Eopnotsupp();
    case "EOVERFLOW":
      return new $simplifile.Eoverflow();
    case "EPERM":
      return new $simplifile.Eperm();
    case "EPIPE":
      return new $simplifile.Epipe();
    case "ERANGE":
      return new $simplifile.Erange();
    case "EROFS":
      return new $simplifile.Erofs();
    case "ESPIPE":
      return new $simplifile.Espipe();
    case "ESRCH":
      return new $simplifile.Esrch();
    case "ESTALE":
      return new $simplifile.Estale();
    case "ETXTBSY":
      return new $simplifile.Etxtbsy();
    case "EXDEV":
      return new $simplifile.Exdev();
    case "NOTUTF8":
      return new $simplifile.NotUtf8();
    default:
      return new $simplifile.Unknown(error_code);
  }
}