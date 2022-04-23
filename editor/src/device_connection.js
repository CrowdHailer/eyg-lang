export async function connectDevice() {
  console.log("connecting");
  let port = await navigator.serial.requestPort({ filters: [] });
  await port.open({ baudRate: 57600 });
  console.log(port.getInfo());
  startReader(port);
  let scan;

  // TODO needs init for state and model of pins
  (async () => {
    const writer = port.writable.getWriter();

    const reset = new Uint8Array([0xff, 0xf9]);
    await writer.write(reset);

    let state = 0;
    while (true) {
      const tick = sleep(500);
      if (scan) {
        const input = null;
        const [output, s] = scan([input, state]);
        state = s;
        console.log(state);
        const set = new Uint8Array([0xf5, 13, binaryToNative(output.Pin13)]);
        await writer.write(set);
      }

      await tick;
    }
    writer.releaseLock();
  })();

  return function setScan(s) {
    scan = s;
  };
}

function isUnit(value) {
  return Array.isArray(value) && value.length === 0;
}
// TODO move with loop code
function binaryToNative(eyg) {
  if (eyg.True && isUnit(eyg.True)) {
    return true;
  } else if (eyg.False && isUnit(eyg.False)) {
  } else {
    throw "Not a boolean";
  }
}

async function startReader(port) {
  while (port.readable) {
    const reader = port.readable.getReader();
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          // Allow the serial port to be closed later.
          reader.releaseLock();
          break;
        }
        if (value) {
          // console.log(value);
          value.forEach((element) => {
            console.log(element, element.toString(16));
          });
        }
      }
    } catch (error) {
      console.warn(error);
      // TODO: Handle non-fatal read error.
    }
  }
}

async function startWrite(port) {
  setTimeout(async () => {
    console.log("Starting write");
    const writer = port.writable.getWriter();

    const data = new Uint8Array([0xff, 0xf9]);
    const r = await writer.write(data);

    await loop(writer);
    // Allow the serial port to be closed later.
    writer.releaseLock();
  }, 0);
}

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
async function loop(writer) {
  while (true) {
    delay = parseInt(document.getElementById("delay").value) * 100;
    console.log(delay);
    const on = new Uint8Array([0xf5, 13, 1]);
    await writer.write(on);
    await sleep(delay);
    const off = new Uint8Array([0xf5, 13, 0]);
    await writer.write(off);
    await sleep(delay);
  }
}
