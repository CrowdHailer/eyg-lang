import * as Firmata from "../../eyg/build/dev/javascript/eyg/dist/firmata/firmata";
import * as Gleam from "../../eyg/build/dev/javascript/eyg/dist/gleam";

export async function connectDevice() {
  console.log("connecting");
  let port = await navigator.serial.requestPort({ filters: [] });
  await port.open({ baudRate: 57600 });
  console.log(port.getInfo());
  startReader(port);
  let scan;

  // TODO needs init for state and model of pins
  (async () => {
    // Firmata needs to be ready and reset before we can do anything
    await sleep(1000);
    const writer = port.writable.getWriter();

    // System Reset
    const reset = new Uint8Array([0xff]);
    await writer.write(reset);
    await sleep(3000);
    // const capability = new Uint8Array([0xf0, 0x6b, 0xf7]);
    // await writer.write(capability);
    // await sleep(3000);
    // const pinstate = new Uint8Array([0xf0, 0x6d, 13, 0xf7]);
    // await writer.write(pinstate);
    // const reportAnalogue = new Uint8Array([0xc0, 0xa0, 1]);
    // await writer.write(reportAnalogue);
    // pull up
    const setMode = new Uint8Array([0xf4, 7, 11]);
    await writer.write(setMode);

    const reportDigital = new Uint8Array([0xd0, 1]);
    await writer.write(reportDigital);

    await sleep(3000);

    console.log("ASKED for capability");
    undefined();
    // const set = new Uint8Array([0xf5, 13, 1]);
    // let r = await writer.write(set);
    // console.log(r);
    // console.log("fooooooooooooooooooo");

    // I think this writes report digital and analoge. one seems to work one not
    // const set = new Uint8Array([0xd0, 0x92, 1, 0xc0, 0xa0, 1]);
    // await writer.write(set);

    let state = 0;
    while (true) {
      const tick = sleep(200);
      if (scan) {
        const input = null;
        const [output, s] = scan([input, state]);
        state = s;
        console.log(state);
        const set = new Uint8Array([
          0xf5,
          12,
          binaryToNative(output.Pin12),
          0xf5,
          13,
          binaryToNative(output.Pin13),
        ]);
        await writer.write(set);
      }

      // turn off the analogue or digital subscription
      // await sleep(5000);

      // const set = new Uint8Array([0xd0, 0x92, 0, 0xc0, 0xa0, 0]);
      // await writer.write(set);
      await tick;
    }
    await sleep(5000);
    console.log("gob");
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
  console.log(Firmata);
  let [parseState, parseMessages] = Firmata.fresh();
  while (port.readable) {
    const reader = port.readable.getReader();
    try {
      while (true) {
        console.log("startread");
        const { value, done } = await reader.read();
        if (done) {
          // Allow the serial port to be closed later.
          reader.releaseLock();
          break;
        }
        if (value) {
          // console.log(value);
          // value.forEach((element) => {
          //   console.log(element, element.toString(16));
          // });

          const parseResult = Firmata.parse(
            new Gleam.BitString(value),
            parseState,
            parseMessages
          );
          parseState = parseResult[0];
          parseMessages = new Gleam.Empty();
          console.log(parseResult[1]);
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
