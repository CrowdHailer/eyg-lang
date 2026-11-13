# Boot boundary

The image uses Linux for hardware drivers and the Gleam EYG runtime for user
programs. Firmware reads `config.txt`, loads the kernel and the initramfs, and
Linux starts `/init`. The initramfs contains the CLI, ARM64 glibc and native init;
the FAT partition supplies firmware and persistent `/data`.

Init mounts `/proc`, `/sys`, `/dev` and `/tmp`, loads configured kernel modules,
sets network and clock state, and launches an EYG shell on each configured
console. It reaps children and restarts shells that exit. SIGTERM powers off,
SIGINT reboots and SIGUSR1 halts after stopping children, saving the clock,
syncing and unmounting `/data`. A shell runs one program in the foreground.

These Linux calls stay in minimal native glue. Exposing `mount`, `wait4` and
`ioctl` as EYG effects would make the language's program interface depend on a
particular operating system. Image construction and checks stay in Gleam;
runtime behavior and interactive examples use the shared interpreter and EYG.

The pattern is similar to [Nerves' erlinit](https://github.com/nerves-project/erlinit):
a small init prepares Linux and starts a language runtime. On a normal Linux
distribution, a service manager can instead launch `eyg` with a terminal and a
persistent working directory. EYG Pi avoids that extra user-space stack.

Replacing Linux with a runtime on bare hardware would also require USB, storage
and networking drivers. A QEMU `virt` experiment could use virtio before a
physical-board port. Effect handling can mediate capabilities, but driver
isolation and scheduling remain host responsibilities.

The CLI's current file, network, time, output, `Prompt` and `ReadKey` effects are
enough for these examples. Pixel presentation, pointer events, concurrent
functions, messages and a portable shutdown request remain design proposals;
this image does not implement them. Any future effect needs a use case and a
contract that also works in other runtimes.
