# EYG Pi

A Raspberry Pi image that boots into the Gleam EYG CLI on HDMI and serial.
EYG examples, image construction, emulator control and recording are Gleam or
EYG. The small [Zig init](./init/init.zig) binds Linux boot operations: mounting,
network configuration, console attachment, child reaping and shutdown.

See the [checked Pi guide](../../guides/embedding_pi.md) for setup, cache behavior
and commands to generate an HDMI recording. The checks use QEMU's Pi 3B;
physical hardware and the included Pi 4 boot assets have not been tested here.

From this directory:

```sh
gleam run -m eyg_pi/build
gleam run -m eyg_pi/emulate
gleam test
eyg script test/pong_test.eyg
```

`build/sd.img` is a new 512 MiB card image; rebuilding replaces it and its data.
`build/` is ignored. Host requirements and network overlays are in the guide.
[DESIGN.md](./DESIGN.md) explains the boot boundary and future directions.
