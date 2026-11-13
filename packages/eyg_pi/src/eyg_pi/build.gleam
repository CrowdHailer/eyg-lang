//// Assemble the boot image in Gleam. Host commands are platform build tools.

import filepath
import gleam/bit_array
import gleam/dict
import gleam/http/request
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import loam/system
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/node/process
import simplifile

const firmware =
  "https://raw.githubusercontent.com/raspberrypi/firmware/12eeaa12865869b07db760f4bbb7507ec6f1976c"

const kernel = "6.18.33-v8+"

const libc =
  "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6_2.39-0ubuntu8.9_arm64.deb"

const boot_files = [
  "bootcode.bin",
  "start.elf",
  "fixup.dat",
  "kernel8.img",
  "bcm2710-rpi-3-b.dtb",
  "bcm2710-rpi-3-b-plus.dtb",
  "bcm2711-rpi-4-b.dtb",
  "start4.elf",
  "fixup4.dat",
]

pub fn main() {
  let assert Ok(host) = process.get()
  let env = process.env(host) |> dict.from_list
  let zig = dict.get(env, "ZIG") |> result.unwrap("zig")
  list.each(["build/downloads/overlays", "build/boot/overlays"], fn(path) {
    let assert Ok(_) = simplifile.create_directory_all(path)
    Nil
  })
  io.println("Fetching pinned firmware, kernel and ARM64 glibc")
  use _ <- promise.await(
    sequence(boot_files, fn(file) {
      fetch(firmware <> "/boot/" <> file, "build/downloads/" <> file)
    }),
  )
  use _ <- promise.await(fetch(
    firmware <> "/boot/overlays/disable-bt.dtbo",
    "build/downloads/overlays/disable-bt.dtbo",
  ))
  use _ <- promise.await(fetch(
    firmware
      <> "/modules/"
      <> kernel
      <> "/kernel/drivers/net/usb/cdc_ether.ko.xz",
    "build/downloads/cdc_ether.ko.xz",
  ))
  use _ <- promise.await(fetch(libc, "build/downloads/libc6.deb"))
  let assert Ok(cwd) = simplifile.current_directory()
  io.println("Compiling the Gleam CLI for ARM64")
  use _ <- promise.await(
    command("../gleam_cli", "gleam", [
      "run",
      "-m",
      "compile",
      "--",
      "bun-linux-arm64",
      filepath.join(cwd, "build/eyg"),
    ]),
  )
  use _ <- promise.await(
    command(".", zig, [
      "build-exe",
      "init/init.zig",
      "-target",
      "aarch64-linux",
      "-O",
      "ReleaseSmall",
      "-fstrip",
      "-femit-bin=build/init",
    ]),
  )
  io.println("Assembling the initramfs")
  list.each(["build/root", "build/glibc"], clean)
  list.each(
    [
      "bin",
      "lib/aarch64-linux-gnu",
      "lib/modules",
      "etc/eyg",
      "proc",
      "sys",
      "dev",
      "tmp",
      "data",
    ],
    fn(path) {
      let assert Ok(_) = simplifile.create_directory_all("build/root/" <> path)
      Nil
    },
  )
  copy("build/init", "build/root/init")
  copy("build/eyg", "build/root/bin/eyg")
  use _ <- promise.await(
    command(".", "dpkg-deb", ["-x", "build/downloads/libc6.deb", "build/glibc"]),
  )
  let gnu = "build/glibc/usr/lib/aarch64-linux-gnu/"
  copy(gnu <> "ld-linux-aarch64.so.1", "build/root/lib/ld-linux-aarch64.so.1")
  list.each(
    [
      "libc.so.6",
      "libm.so.6",
      "libpthread.so.0",
      "libdl.so.2",
      "libnss_dns.so.2",
      "libnss_files.so.2",
      "libresolv.so.2",
    ],
    fn(file) { copy(gnu <> file, "build/root/lib/aarch64-linux-gnu/" <> file) },
  )
  use module <- promise.await(
    binary(".", ["xz", "-dc", "build/downloads/cdc_ether.ko.xz"], <<>>),
  )
  let assert Ok(_) =
    simplifile.write_bits("build/root/lib/modules/cdc_ether.ko", module)
  let assert Ok(_) =
    simplifile.create_symlink("/proc/net/pnp", "build/root/etc/resolv.conf")
  write("build/root/etc/nsswitch.conf", "hosts: files dns\n")
  write("build/root/etc/hosts", "127.0.0.1 localhost\n")
  write("build/root/etc/eyg/environment", "")
  use now <- promise.await(system.run(system.now()))
  write("build/root/etc/eyg/build-time", int.to_string(now / 1000) <> "\n")
  use _ <- promise.await(case dict.get(env, "EYG_PI_OVERLAY") {
    Ok(overlay) -> command(".", "cp", ["-a", overlay <> "/.", "build/root/"])
    Error(_) -> promise.resolve(Nil)
  })
  let paths =
    tree("build/root", ".") |> list.sort(string.compare) |> string.join("\n")
  use archive <- promise.await(binary(
    "build/root",
    ["cpio", "--quiet", "-o", "-H", "newc", "-R", "0:0"],
    bit_array.from_string(paths <> "\n"),
  ))
  use compressed <- promise.await(binary(".", ["gzip", "-6"], archive))
  let assert Ok(_) =
    simplifile.write_bits("build/boot/initramfs.gz", compressed)
  list.each(boot_files, fn(file) {
    copy("build/downloads/" <> file, "build/boot/" <> file)
  })
  copy(
    "build/downloads/overlays/disable-bt.dtbo",
    "build/boot/overlays/disable-bt.dtbo",
  )
  copy("boot/config.txt", "build/boot/config.txt")
  copy("boot/cmdline.txt", "build/boot/cmdline.txt")
  use _ <- promise.await(
    command(".", "fdtoverlay", [
      "-i",
      "build/boot/bcm2710-rpi-3-b.dtb",
      "-o",
      "build/qemu.dtb",
      "build/boot/overlays/disable-bt.dtbo",
    ]),
  )
  io.println("Assembling the 512 MiB SD card image")
  clean("build/sd.img")
  use _ <- promise.await(
    command(".", "truncate", ["-s", "512M", "build/sd.img"]),
  )
  use _ <- promise.await(
    binary(".", ["sfdisk", "--quiet", "build/sd.img"], <<
      "label: dos\nstart=2048, type=c, bootable\n":utf8,
    >>),
  )
  use _ <- promise.await(
    command(".", "mformat", [
      "-i",
      "build/sd.img@@1048576",
      "-F",
      "-v",
      "EYG",
      "::",
    ]),
  )
  let assert Ok(files) = simplifile.read_directory("build/boot")
  use _ <- promise.await(
    sequence(files, fn(file) {
      command(".", "mcopy", [
        "-i",
        "build/sd.img@@1048576",
        "-s",
        "build/boot/" <> file,
        "::",
      ])
    }),
  )
  use _ <- promise.map(
    command(".", "mcopy", [
      "-i",
      "build/sd.img@@1048576",
      "-s",
      "examples",
      "::",
    ]),
  )
  io.println("Built build/sd.img")
}

fn clean(path) {
  let assert Ok(exists) = simplifile.exists(path, False)
  case exists {
    True -> {
      let assert Ok(_) = simplifile.delete(path)
      Nil
    }
    False -> Nil
  }
}

fn copy(from, to) {
  let assert Ok(_) = simplifile.copy_file(from, to)
  Nil
}

fn write(path, text) {
  let assert Ok(_) = simplifile.write(path, text)
  Nil
}

fn tree(root, relative) {
  let assert Ok(entries) =
    simplifile.read_directory(filepath.join(root, relative))
  [
    relative,
    ..list.flat_map(entries, fn(name) {
      let relative = filepath.join(relative, name)
      let assert Ok(info) = simplifile.link_info(filepath.join(root, relative))
      case simplifile.file_info_type(info) {
        simplifile.Directory -> tree(root, relative)
        _ -> [relative]
      }
    })
  ]
}

fn fetch(url, path) {
  case simplifile.exists(path, True) {
    Ok(True) -> promise.resolve(Nil)
    _ -> {
      let assert Ok(request) = request.to(url)
      use response <- promise.map(
        system.run(system.fetch(request.set_body(request, <<>>))),
      )
      let assert Ok(response) = response
      assert response.status == 200 as url
      let assert Ok(_) = simplifile.write_bits(path, response.body)
      Nil
    }
  }
}

pub fn command(cwd, program, args) {
  use outcome <- promise.map(system.run(system.command(program, args, cwd)))
  let assert Ok(output) = outcome
  case string.trim(output) {
    "" -> Nil
    output -> io.println(output)
  }
}

fn binary(cwd, cmd, input) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let assert Ok(child) =
    subprocess.spawn_with_input(
      bun,
      subprocess.Options(cmd, cwd, process.env(host), "pipe", "pipe", "pipe"),
      input,
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  use output <- promise.await(subprocess.readable_stream_to_bits(bun, stdout))
  use errors <- promise.await(subprocess.readable_stream_to_text(bun, stderr))
  use exited <- promise.map(subprocess.exited(child))
  let assert Ok(0) = exited as string.inspect(errors)
  let assert Ok(output) = output
  output
}

fn sequence(items, work) {
  case items {
    [] -> promise.resolve(Nil)
    [item, ..rest] -> {
      use _ <- promise.await(work(item))
      sequence(rest, work)
    }
  }
}
