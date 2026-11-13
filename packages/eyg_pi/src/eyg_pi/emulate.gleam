//// Start QEMU with the same kernel, firmware overlay and persistent card as hardware.

import argv
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/result
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/node/process

pub fn arguments(offline: Bool, headless: Bool, serial: String) {
  let network = case offline {
    True -> "user,id=net0,restrict=on"
    False -> "user,id=net0"
  }
  let display = case headless {
    True -> ["-display", "none"]
    False -> []
  }
  let cmdline =
    "console=ttyAMA0,115200 console=tty1 eyg.data=/dev/mmcblk0p1 quiet eyg.module=cdc_ether eyg.net=usb0:10.0.2.15/24:10.0.2.2:10.0.2.3 eyg.ntp=216.239.35.0 dwc_otg.fiq_fsm_enable=0 dwc_otg.fiq_enable=0"
  [
    "qemu-system-aarch64",
    "-M",
    "raspi3b",
    "-m",
    "1G",
    "-kernel",
    "build/boot/kernel8.img",
    "-dtb",
    "build/qemu.dtb",
    "-initrd",
    "build/boot/initramfs.gz",
    "-append",
    cmdline,
    "-drive",
    "file=build/sd.img,if=sd,format=raw",
    "-usb",
    "-device",
    "usb-kbd",
    "-device",
    "usb-net,netdev=net0",
    "-netdev",
    network,
    "-serial",
    serial,
    ..display
  ]
}

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  let config = dict.from_list(env)
  let offline = dict.get(config, "EYG_PI_OFFLINE") == Ok("1")
  let headless = dict.get(config, "EYG_PI_HEADLESS") == Ok("1")
  let serial = dict.get(config, "EYG_PI_SERIAL") |> result.unwrap("mon:stdio")
  let cmd =
    list.append(arguments(offline, headless, serial), argv.load().arguments)
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(cmd, ".", env, "inherit", "inherit", "inherit"),
    )
  use status <- promise.map(subprocess.exited(child))
  let assert Ok(status) = status
  process.set_exit_code(host, status)
}
