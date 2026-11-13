//! PID 1 for an EYG computer.
//!
//! The kernel starts this program first. Its only jobs are those that no other process can do:
//! prepare the kernel interfaces (/proc, /dev, ...), bring up storage and network,
//! start an EYG shell on every console, reap orphaned processes and shut the machine down.
//! Everything a user does happens in EYG.
//!
//! Configuration comes from the kernel command line so the SD card is the only thing to edit.
//!
//!   console=tty1 console=ttyAMA0,115200  an EYG shell is started on each console
//!   eyg.data=/dev/mmcblk0p1               vfat partition mounted at /data, holds the hub cache
//!   eyg.net=eth0:10.0.2.15/24:10.0.2.2:10.0.2.3  static network, interface:address/prefix:gateway:dns
//!   eyg.module=cdc_ether                  load /lib/modules/<name>.ko before networking, can repeat
//!   eyg.ntp=216.239.35.0                  set the clock from this SNTP server (an IP address)
//!
//! With `ip=dhcp` the kernel configures a built-in network driver itself and eyg.net is not needed.

const std = @import("std");
const linux = std.os.linux;

const shell = "/bin/eyg";
const max_consoles = 4;

var shutdown_request: ?linux.LINUX_REBOOT.CMD = null;

pub fn main() noreturn {
    mount("proc", "/proc", "proc", "");
    mount("sysfs", "/sys", "sysfs", "");
    mount("devtmpfs", "/dev", "devtmpfs", "");
    mount("tmpfs", "/tmp", "tmpfs", "mode=1777");
    log("eyg init starting", .{});
    handle_signals();

    var cmdline_buffer: [4096]u8 = undefined;
    const cmdline = read_file("/proc/cmdline", &cmdline_buffer) orelse "";

    var consoles: [max_consoles][]const u8 = undefined;
    var console_count: usize = 0;
    var args = std.mem.tokenizeAny(u8, cmdline, " \n");
    while (args.next()) |arg| {
        if (value(arg, "eyg.module=")) |name| load_module(name);
    }
    args.reset();
    while (args.next()) |arg| {
        if (value(arg, "console=")) |c| {
            const name = c[0 .. std.mem.indexOfScalar(u8, c, ',') orelse c.len];
            if (console_count < max_consoles) {
                consoles[console_count] = name;
                console_count += 1;
            }
        } else if (value(arg, "eyg.data=")) |device| {
            mount_data(device);
        } else if (value(arg, "eyg.net=")) |config| {
            configure_network(config);
        }
    }
    bring_up("lo", null, null);

    // The Pi has no battery backed clock and TLS needs the current time.
    // Start from the newest known time, then ask a time server if one is configured.
    set_clock(@max(read_seconds("/etc/eyg/build-time"), read_seconds(saved_clock)));
    args.reset();
    while (args.next()) |arg| {
        if (value(arg, "eyg.ntp=")) |server| sntp(server);
    }

    // Kernel messages written to a console would break into the shell's output.
    // From here only emergencies are shown, everything stays readable in the kernel log.
    _ = linux.syscall3(.syslog, 8, 0, 1); // SYSLOG_ACTION_CONSOLE_LEVEL

    var sessions = [_]linux.pid_t{0} ** max_consoles;
    for (consoles[0..console_count], 0..) |console, i| sessions[i] = spawn(console);

    // The kernel re-parents every orphaned process to PID 1, they become zombies until waited on.
    // Waiting on any child (-1) reaps them all, shells that exit are restarted.
    while (true) {
        if (shutdown_request) |cmd| shutdown(cmd);
        var status: u32 = 0;
        const rc = linux.wait4(-1, &status, 0, null);
        if (failed(rc)) {
            // EINTR from a signal, or ECHILD when there are no children.
            if (linux.E.init(rc) == .CHILD) sleep_ms(1000);
            continue;
        }
        const pid: linux.pid_t = @intCast(rc);
        for (sessions[0..console_count], 0..) |session, i| {
            if (session == pid) {
                log("shell on {s} exited, restarting", .{consoles[i]});
                sleep_ms(500);
                sessions[i] = spawn(consoles[i]);
            }
        }
    }
}

const saved_clock = "/data/.clock";

fn read_seconds(path: [*:0]const u8) i64 {
    var buffer: [32]u8 = undefined;
    const text = read_file(path, &buffer) orelse return 0;
    return std.fmt.parseInt(i64, std.mem.trim(u8, text, " \n"), 10) catch 0;
}

fn set_clock(seconds: i64) void {
    if (seconds <= 0) return;
    const ts = linux.timespec{ .sec = @intCast(seconds), .nsec = 0 };
    check(linux.clock_settime(@intFromEnum(linux.CLOCK.REALTIME), &ts), "set clock");
}

fn save_clock() void {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(linux.CLOCK.REALTIME, &ts))) return;
    var buffer: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}\n", .{ts.sec}) catch return;
    write_file(saved_clock, text);
}

/// Simple Network Time Protocol, one request and the server's transmit time is used.
fn sntp(server: []const u8) void {
    const address = parse_ip(server) orelse return log("bad ntp server {s}", .{server});
    const sock_rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(sock_rc)) return;
    const sock: i32 = @intCast(sock_rc);
    defer _ = linux.close(sock);
    const timeout = linux.timeval{ .sec = 3, .usec = 0 };
    _ = linux.setsockopt(sock, linux.SOL.SOCKET, linux.SO.RCVTIMEO, std.mem.asBytes(&timeout), @sizeOf(linux.timeval));
    var packet = [_]u8{0} ** 48;
    packet[0] = 0x1b; // version 3, client mode
    const to: linux.sockaddr = @bitCast(linux.sockaddr.in{ .port = std.mem.nativeToBig(u16, 123), .addr = address });
    if (failed(linux.sendto(sock, &packet, packet.len, 0, &to, @sizeOf(linux.sockaddr)))) return log("ntp send failed", .{});
    const n = linux.recvfrom(sock, &packet, packet.len, 0, null, null);
    if (failed(n) or n < 48) return log("no reply from ntp server {s}", .{server});
    const since_1900 = std.mem.readInt(u32, packet[40..44], .big);
    set_clock(@as(i64, since_1900) - 2_208_988_800);
    save_clock();
    log("clock set from {s}", .{server});
}

fn spawn(console: []const u8) linux.pid_t {
    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buffer, "/dev/{s}", .{console}) catch return 0;
    const rc = linux.fork();
    if (failed(rc)) {
        log("fork failed", .{});
        return 0;
    }
    if (rc != 0) return @intCast(rc);

    // Child: become a session leader with the console as controlling terminal.
    _ = linux.setsid();
    const fd_rc = linux.open(path, .{ .ACCMODE = .RDWR }, 0);
    if (failed(fd_rc)) linux.exit(1);
    const fd: i32 = @intCast(fd_rc);
    _ = linux.ioctl(fd, linux.T.IOCSCTTY, 0);
    _ = linux.dup2(fd, 0);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);
    // Clear boot messages so the shell starts on an empty screen.
    const clear = "\x1b[2J\x1b[H";
    _ = linux.write(1, clear, clear.len);

    // Start in /data so files written from the shell persist.
    _ = linux.chdir("/data");
    var env_storage: [2048]u8 = undefined;
    var envp: [24:null]?[*:0]const u8 = undefined;
    load_environment(&env_storage, &envp);
    const argv = [_:null]?[*:0]const u8{shell};
    _ = linux.execve(shell, &argv, &envp);
    linux.exit(127);
}

/// Environment for the shells, defaults followed by lines of /etc/eyg/environment.
fn load_environment(storage: []u8, envp: *[24:null]?[*:0]const u8) void {
    const defaults = [_][*:0]const u8{
        "HOME=/data",
        "TERM=linux",
        "XDG_CACHE_HOME=/data/cache",
        "XDG_CONFIG_HOME=/data/config",
    };
    var count: usize = 0;
    for (defaults) |entry| {
        envp[count] = entry;
        count += 1;
    }
    var file_buffer: [1024]u8 = undefined;
    const contents = read_file("/etc/eyg/environment", &file_buffer) orelse "";
    var used: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#' or count + 1 >= envp.len) continue;
        if (used + line.len + 1 > storage.len) break;
        @memcpy(storage[used .. used + line.len], line);
        storage[used + line.len] = 0;
        envp[count] = @ptrCast(storage[used..].ptr);
        used += line.len + 1;
        count += 1;
    }
    envp[count] = null;
}

fn mount_data(device: []const u8) void {
    var buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buffer, "{s}", .{device}) catch return;
    // Storage drivers probe in parallel with init, wait for the device node to appear.
    if (!wait_for(path)) {
        log("data device {s} not found, using memory", .{device});
        return;
    }
    const rc = linux.mount(path, "/data", "vfat", 0, @intFromPtr("utf8"));
    if (failed(rc)) log("mount {s} failed: {s}", .{ device, @tagName(linux.E.init(rc)) });
}

fn load_module(name: []const u8) void {
    var buffer: [128]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buffer, "/lib/modules/{s}.ko", .{name}) catch return;
    const fd_rc = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(fd_rc)) return log("module {s} not found", .{name});
    const fd: i32 = @intCast(fd_rc);
    defer _ = linux.close(fd);
    const rc = linux.syscall3(.finit_module, @intCast(fd), @intFromPtr(""), 0);
    if (failed(rc)) log("module {s}: {s}", .{ name, @tagName(linux.E.init(rc)) });
}

/// Parse `interface:address/prefix:gateway:dns`.
fn configure_network(config: []const u8) void {
    var parts = std.mem.splitScalar(u8, config, ':');
    const name = parts.next() orelse return;
    const cidr = parts.next() orelse return;
    const gateway = parts.next();
    const dns = parts.next();
    const slash = std.mem.indexOfScalar(u8, cidr, '/') orelse cidr.len;
    const address = parse_ip(cidr[0..slash]) orelse return log("bad address {s}", .{cidr});
    const prefix = if (slash < cidr.len) std.fmt.parseInt(u5, cidr[slash + 1 ..], 10) catch 24 else 24;

    var sys_path: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&sys_path, "/sys/class/net/{s}", .{name}) catch return;
    // USB network adapters enumerate after init has started.
    if (!wait_for(path)) return log("network interface {s} not found", .{name});
    const mask: u32 = if (prefix == 0) 0 else ~@as(u32, 0) << @intCast(@as(u6, 32) - prefix);
    bring_up(name, address, std.mem.nativeToBig(u32, mask));
    if (gateway) |g| if (parse_ip(g)) |gw| add_default_route(gw);
    if (dns) |d| {
        var resolv: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&resolv, "nameserver {s}\n", .{d}) catch return;
        write_file("/etc/resolv.conf", text);
    }
    log("network {s} configured", .{name});
}

fn bring_up(name: []const u8, address: ?u32, netmask: ?u32) void {
    const sock_rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(sock_rc)) return;
    const sock: i32 = @intCast(sock_rc);
    defer _ = linux.close(sock);
    var request = std.mem.zeroes(linux.ifreq);
    @memcpy(request.ifrn.name[0..name.len], name);
    if (address) |a| {
        request.ifru.addr = @bitCast(linux.sockaddr.in{ .port = 0, .addr = a });
        check(linux.ioctl(sock, linux.SIOCSIFADDR, @intFromPtr(&request)), "set address");
    }
    if (netmask) |m| {
        request.ifru.netmask = @bitCast(linux.sockaddr.in{ .port = 0, .addr = m });
        check(linux.ioctl(sock, linux.SIOCSIFNETMASK, @intFromPtr(&request)), "set netmask");
    }
    request.ifru.flags = .{ .UP = true, .RUNNING = true };
    check(linux.ioctl(sock, linux.SIOCSIFFLAGS, @intFromPtr(&request)), "interface up");
}

const rtentry = extern struct {
    pad1: usize = 0,
    dst: linux.sockaddr,
    gateway: linux.sockaddr,
    genmask: linux.sockaddr,
    flags: u16,
    pad2: i16 = 0,
    pad3: usize = 0,
    pad4: usize = 0,
    metric: i16 = 0,
    dev: usize = 0,
    mtu: usize = 0,
    window: usize = 0,
    irtt: u16 = 0,
};

fn add_default_route(gateway: u32) void {
    const sock_rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(sock_rc)) return;
    const sock: i32 = @intCast(sock_rc);
    defer _ = linux.close(sock);
    const any: linux.sockaddr = @bitCast(linux.sockaddr.in{ .port = 0, .addr = 0 });
    var route = rtentry{
        .dst = any,
        .genmask = any,
        .gateway = @bitCast(linux.sockaddr.in{ .port = 0, .addr = gateway }),
        .flags = 0x0001 | 0x0002, // RTF_UP | RTF_GATEWAY
    };
    check(linux.ioctl(sock, linux.SIOCADDRT, @intFromPtr(&route)), "default route");
}

fn parse_ip(text: []const u8) ?u32 {
    const address = std.net.Ip4Address.parse(text, 0) catch return null;
    return address.sa.addr;
}

/// The kernel only delivers signals to PID 1 that it has installed handlers for.
/// SIGTERM powers off, SIGINT (Ctrl-Alt-Del once CAD is off) reboots.
fn handle_signals() void {
    _ = linux.reboot(.MAGIC1, .MAGIC2, .CAD_OFF, null);
    const action = linux.Sigaction{
        .handler = .{ .handler = on_signal },
        .mask = linux.empty_sigset,
        .flags = 0,
    };
    _ = linux.sigaction(linux.SIG.TERM, &action, null);
    _ = linux.sigaction(linux.SIG.INT, &action, null);
    _ = linux.sigaction(linux.SIG.USR1, &action, null);
}

fn on_signal(signal: i32) callconv(.c) void {
    shutdown_request = switch (signal) {
        linux.SIG.INT => .RESTART,
        linux.SIG.USR1 => .HALT,
        else => .POWER_OFF,
    };
}

fn shutdown(cmd: linux.LINUX_REBOOT.CMD) noreturn {
    log("shutting down", .{});
    _ = linux.kill(-1, linux.SIG.TERM);
    sleep_ms(2000);
    _ = linux.kill(-1, linux.SIG.KILL);
    save_clock();
    linux.sync();
    _ = linux.umount2("/data", 0);
    _ = linux.reboot(.MAGIC1, .MAGIC2, cmd, null);
    // Returning from PID 1 panics the kernel, so never return.
    while (true) sleep_ms(1000);
}

// Helpers

fn value(arg: []const u8, key: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, arg, key)) arg[key.len..] else null;
}

fn mount(source: [*:0]const u8, target: [*:0]const u8, fstype: [*:0]const u8, data: [*:0]const u8) void {
    _ = linux.mkdir(target, 0o755);
    const rc = linux.mount(source, target, fstype, 0, @intFromPtr(data));
    if (failed(rc) and linux.E.init(rc) != .BUSY) log("mount {s} failed", .{target});
}

fn wait_for(path: [*:0]const u8) bool {
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        if (linux.access(path, 0) == 0) return true;
        sleep_ms(100);
    }
    return false;
}

fn read_file(path: [*:0]const u8, buffer: []u8) ?[]const u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    const n = linux.read(fd, buffer.ptr, buffer.len);
    if (failed(n)) return null;
    return buffer[0..n];
}

/// Replaces the file, /etc/resolv.conf starts as a symlink to the kernel's DHCP result.
fn write_file(path: [*:0]const u8, contents: []const u8) void {
    _ = linux.unlink(path);
    const rc = linux.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) return;
    const fd: i32 = @intCast(rc);
    _ = linux.write(fd, contents.ptr, contents.len);
    _ = linux.close(fd);
}

fn sleep_ms(ms: u64) void {
    const ts = linux.timespec{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

fn failed(rc: usize) bool {
    return linux.E.init(rc) != .SUCCESS;
}

fn check(rc: usize, what: []const u8) void {
    if (failed(rc)) log("{s}: {s}", .{ what, @tagName(linux.E.init(rc)) });
}

/// Messages go to the kernel log, which is shown on every console.
fn log(comptime format: []const u8, args: anytype) void {
    var buffer: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "<5>init: " ++ format ++ "\n", args) catch return;
    const rc = linux.open("/dev/kmsg", .{ .ACCMODE = .WRONLY }, 0);
    if (failed(rc)) {
        _ = linux.write(1, text.ptr, text.len);
        return;
    }
    const fd: i32 = @intCast(rc);
    _ = linux.write(fd, text.ptr, text.len);
    _ = linux.close(fd);
}
