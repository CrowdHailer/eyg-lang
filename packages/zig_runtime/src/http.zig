//! Native implementation of touch_grass Fetch. Networking remains an effect;
//! requests use configured proxies and verified TLS with the host CA bundle.
const std = @import("std");
const builtin = @import("builtin");
const interpreter = @import("interpreter.zig");
pub const Engine = interpreter.Engine;
const V = interpreter.Value;
const A = std.mem.Allocator;
const maximum_body = 64 * 1024 * 1024;
const maximum_headers = 64 * 1024;
const maximum_redirects = 20;

/// Match touch_grass/fetch: Result({status,headers,body}, String).
/// Network, protocol and malformed-request errors are values, not interpreter
/// panics. OutOfMemory remains an allocation error for the embedding host.
pub fn effect(engine: *Engine, lift: V) !V {
    const response = perform(engine, lift) catch |err| {
        if (err == error.OutOfMemory) return err;
        return engine.tag("Error", .{ .string = try errorMessage(engine.allocator, lift, err) });
    };
    return engine.tag("Ok", response);
}

/// Shared GET transport for native effect hosts, including the read-only hub.
/// Returned storage belongs to `a`; network/protocol errors propagate normally.
pub const Response = struct { status: u16, headers: []const std.http.Header, body: []const u8 };
pub fn get(a: A, url: []const u8) !Response {
    const uri = try std.Uri.parse(url);
    if (uri.user != null or uri.password != null) return error.UrlCredentialsForbidden;
    const scheme = if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) "HTTPS" else if (std.ascii.eqlIgnoreCase(uri.scheme, "http")) "HTTP" else return error.UnsupportedUriScheme;
    var engine = Engine.init(a);
    const lift = try record(a, &.{
        .{ .name = "method", .value = try engine.tag("GET", interpreter.unit()) },
        .{ .name = "scheme", .value = try engine.tag(scheme, interpreter.unit()) },
        .{ .name = "host", .value = .{ .string = try (uri.host orelse return error.UriMissingHost).toRawMaybeAlloc(a) } },
        .{ .name = "port", .value = if (uri.port) |port| try engine.tag("Some", .{ .integer = port }) else try engine.tag("None", interpreter.unit()) },
        .{ .name = "path", .value = .{ .string = componentBytes(uri.path) } },
        .{ .name = "query", .value = if (uri.query) |query| try engine.tag("Some", .{ .string = componentBytes(query) }) else try engine.tag("None", interpreter.unit()) },
        .{ .name = "headers", .value = .{ .list = null } },
        .{ .name = "body", .value = .{ .binary = "" } },
    });
    const response = try perform(&engine, lift);
    const status = try field(response, "status");
    const body = try field(response, "body");
    var values = (try field(response, "headers")).list;
    var headers = std.ArrayList(std.http.Header).init(a);
    while (values) |cell| : (values = cell.tail) try headers.append(.{ .name = try string(try field(cell.head, "key")), .value = try string(try field(cell.head, "value")) });
    return .{ .status = @intCast(status.integer), .headers = try headers.toOwnedSlice(), .body = body.binary };
}

fn perform(engine: *Engine, lift: V) !V {
    // Release sockets, certificate parsing and request metadata after this
    // operation even when the interpreter itself owns a long-lived arena.
    var temporary = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer temporary.deinit();
    const a = temporary.allocator();
    var uri = try requestUri(a, lift);
    var method = try methodName(a, try field(lift, "method"));
    const input_body = try field(lift, "body");
    if (input_body != .binary) return error.InvalidFetchBody;
    var body = if (std.mem.eql(u8, method, "GET") or std.mem.eql(u8, method, "HEAD")) @as([]const u8, "") else input_body.binary;
    if (std.mem.eql(u8, method, "OPTIONS") and body.len != 0) return error.OptionsBodyUnsupported;
    var headers = try requestHeaders(a, try field(lift, "headers"));
    var client = std.http.Client{ .allocator = a };
    defer client.deinit();
    try client.initDefaultProxies(a);
    const http_proxy = client.http_proxy;
    const https_proxy = client.https_proxy;
    const no_proxy = try environment(a, &.{ "no_proxy", "NO_PROXY" });
    var trust_ready = false;

    for (0..maximum_redirects + 1) |redirects| {
        if (!std.ascii.eqlIgnoreCase(uri.scheme, "http") and !std.ascii.eqlIgnoreCase(uri.scheme, "https")) return error.UnsupportedUriScheme;
        if (uri.user != null or uri.password != null) return error.UrlCredentialsForbidden;
        const host = try (uri.host orelse return error.UriMissingHost).toRawMaybeAlloc(a);
        if (host.len == 0 or std.mem.indexOfAny(u8, host, "\r\n\x00") != null) return error.InvalidFetchHost;
        const port = uri.port orelse if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) @as(u16, 443) else 80;
        const direct = noProxyMatches(no_proxy orelse "", host, port);
        client.http_proxy = if (direct) null else http_proxy;
        client.https_proxy = if (direct) null else https_proxy;
        // Plain HTTP uses the proxy absolute-form request, not a CONNECT.
        if (client.http_proxy) |proxy| proxy.supports_connect = false;
        if (!trust_ready and std.ascii.eqlIgnoreCase(uri.scheme, "https")) {
            try configureTrust(&client, a);
            trust_ready = true;
        }
        var standard_headers = std.http.Client.Request.Headers{};
        standard_headers.authorization = .omit;
        if (hasHeader(headers.items, "host")) standard_headers.host = .omit;
        if (hasHeader(headers.items, "user-agent")) standard_headers.user_agent = .omit;
        if (hasHeader(headers.items, "connection")) standard_headers.connection = .omit;
        if (hasHeader(headers.items, "accept-encoding")) standard_headers.accept_encoding = .omit;
        if (hasHeader(headers.items, "content-type")) standard_headers.content_type = .omit;
        var outgoing = std.ArrayList(std.http.Header).init(a);
        try outgoing.appendSlice(headers.items);
        const send_body = !std.mem.eql(u8, method, "GET") and !std.mem.eql(u8, method, "HEAD");
        if (send_body) try outgoing.append(.{ .name = "content-length", .value = try std.fmt.allocPrint(a, "{d}", .{body.len}) });
        const header_buffer = try a.alloc(u8, maximum_headers);
        const connection: ?*std.http.Client.Connection = if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) tunnel: {
            if (client.https_proxy) |proxy| switch (try tlsTunnel(&client, proxy, uri, a, engine)) {
                .connection => |conn| break :tunnel conn,
                .response => |response| return response,
            };
            break :tunnel try directTls(&client, uri, a);
        } else null;
        var req = client.open(if (method.len <= 8) @enumFromInt(std.http.Method.parse(method)) else .POST, uri, .{
            .server_header_buffer = header_buffer,
            .connection = connection,
            .redirect_behavior = .unhandled,
            .headers = standard_headers,
            .extra_headers = outgoing.items,
            .keep_alive = false,
        }) catch |err| {
            if (connection) |owned| {
                owned.closing = true;
                client.connection_pool.release(a, owned);
            }
            return err;
        };
        defer req.deinit();
        // std.http 0.14 disallows bodies for DELETE/OPTIONS even though fetch
        // permits them. We write their known-length payload through the same
        // acquired connection, with Content-Length emitted above.
        if (method.len <= 8) try req.send() else try sendLongMethod(&req, method, outgoing.items);
        if (send_body and body.len != 0) try req.connection.?.writer().writeAll(body);
        try req.finish();
        try req.wait();
        const code: u16 = @intFromEnum(req.response.status);
        if (isRedirect(code)) {
            const location = req.response.location orelse return responseValue(engine, &req);
            if (redirects == maximum_redirects) return error.TooManyHttpRedirects;
            // The location points into the response buffer; give the resolver
            // fresh storage that survives this request's deinitialization.
            const base_size = componentBytes(uri.path).len;
            var scratch = try a.alloc(u8, maximum_headers + base_size + location.len + 128);
            const next = try uri.resolve_inplace(location, &scratch);
            if (!sameOrigin(uri, next, a)) stripSensitive(&headers);
            const drop_body = code == 303 and !std.mem.eql(u8, method, "GET") and !std.mem.eql(u8, method, "HEAD") or ((code == 301 or code == 302) and std.mem.eql(u8, method, "POST"));
            if (drop_body) {
                method = "GET";
                body = "";
                stripBodyHeaders(&headers);
            }
            uri = next;
            continue;
        }
        return responseValue(engine, &req);
    }
    return error.TooManyHttpRedirects;
}

// Keep the TLS verifier's specific error instead of std.http's generic
// TlsInitializationFailed wrapper, so Fetch can retain oracle diagnostics.
fn directTls(client: *std.http.Client, uri: std.Uri, a: A) !*std.http.Client.Connection {
    const host = try (uri.host orelse return error.UriMissingHost).toRawMaybeAlloc(a);
    const conn = try client.connectTcp(host, uri.port orelse 443, .plain);
    errdefer {
        conn.closing = true;
        client.connection_pool.release(a, conn);
    }
    const tls = try a.create(std.crypto.tls.Client);
    errdefer a.destroy(tls);
    tls.* = try std.crypto.tls.Client.init(conn.stream, .{ .host = .{ .explicit = host }, .ca = .{ .bundle = client.ca_bundle } });
    tls.allow_truncation_attacks = true;
    conn.tls_client = tls;
    conn.protocol = .tls;
    return conn;
}

fn errorMessage(a: A, lift: V, err: anyerror) ![]const u8 {
    const message: []const u8 = switch (err) {
        error.ConnectionRefused => "Error: Unable to connect. Is the computer able to access the url?",
        error.CertificateIssuerNotFound, error.TlsCertificateNotVerified => "Error: unable to verify the first certificate",
        error.TooManyHttpRedirects => "Error: The response redirected too many times. For more information, pass `verbose: true` in the second argument to fetch()",
        error.OptionsBodyUnsupported => "TypeError [ERR_INVALID_ARG_VALUE]: fetch() request with GET/HEAD/OPTIONS method cannot have body.",
        error.CertificateHostMismatch => blk: {
            const uri = requestUri(a, lift) catch return @errorName(err);
            const url = try std.fmt.allocPrint(a, "{}", .{uri});
            break :blk try std.fmt.allocPrint(a, "Error: ERR_TLS_CERT_ALTNAME_INVALID fetching \"{s}\". For more information, pass `verbose: true` in the second argument to fetch()", .{url});
        },
        else => return @errorName(err),
    };
    const inspected = try std.json.stringifyAlloc(a, message, .{});
    return std.fmt.allocPrint(a, "NetworkError({s})", .{inspected});
}

// Zig 0.14's stock CONNECT helper leaves the tunnel at the proxy's transport
// protocol and does not send proxy authorization on CONNECT. Establish the
// tunnel explicitly, then verify the origin through native TLS. Never fall
// back to a plaintext HTTPS request or a direct connection after proxy failure.
const Tunnel = union(enum) { connection: *std.http.Client.Connection, response: V };
fn tlsTunnel(client: *std.http.Client, proxy: *std.http.Client.Proxy, uri: std.Uri, a: A, engine: *Engine) !Tunnel {
    if (proxy.protocol != .plain) return error.HttpsProxyTransportUnsupported;
    const host = try (uri.host orelse return error.UriMissingHost).toRawMaybeAlloc(a);
    const port = uri.port orelse 443;
    const conn = try client.connectTcp(proxy.host, proxy.port, .plain);
    var buffer: [maximum_headers]u8 = undefined;
    const auth: []const std.http.Header = if (proxy.authorization) |value| &.{.{ .name = "proxy-authorization", .value = value }} else &.{};
    var tunnel = client.open(.CONNECT, .{ .scheme = "http", .host = .{ .raw = host }, .port = port }, .{
        .connection = conn,
        .server_header_buffer = &buffer,
        .redirect_behavior = .unhandled,
        .extra_headers = auth,
        .keep_alive = false,
    }) catch |err| {
        conn.closing = true;
        client.connection_pool.release(a, conn);
        return err;
    };
    defer tunnel.deinit();
    try tunnel.send();
    try tunnel.finish();
    try tunnel.wait();
    // Bun exposes a refused CONNECT as its HTTP response. Retain that
    // observable result without sending an origin request or retrying directly.
    if (tunnel.response.status != .ok) return .{ .response = try responseValue(engine, &tunnel) };
    tunnel.connection = null;
    errdefer {
        conn.closing = true;
        client.connection_pool.release(a, conn);
    }
    const tls = try a.create(std.crypto.tls.Client);
    errdefer a.destroy(tls);
    tls.* = try std.crypto.tls.Client.init(conn.stream, .{ .host = .{ .explicit = host }, .ca = .{ .bundle = client.ca_bundle } });
    tls.allow_truncation_attacks = true; // HTTP framing detects incomplete bodies.
    const name = try a.dupe(u8, host);
    a.free(conn.host);
    conn.host = name;
    conn.port = port;
    conn.tls_client = tls;
    conn.protocol = .tls;
    conn.proxied = false;
    conn.closing = false;
    return .{ .connection = conn };
}

// The std.http Method enum stores at most eight bytes. Keep the standard
// connection, parser and TLS machinery for longer extension methods and emit
// their request line without truncation. The parser uses POST's body rules.
fn sendLongMethod(req: *std.http.Client.Request, method: []const u8, headers: []const std.http.Header) !void {
    const conn = req.connection.?;
    const writer = conn.writer();
    try writer.print("{s} ", .{method});
    try req.uri.writeToStream(.{ .scheme = conn.proxied, .authentication = false, .authority = conn.proxied, .path = true, .query = true }, writer);
    try writer.writeAll(" HTTP/1.1\r\n");
    if (!hasHeader(headers, "host")) {
        try writer.writeAll("host: ");
        try req.uri.writeToStream(.{ .authority = true }, writer);
        try writer.writeAll("\r\n");
    }
    if (!hasHeader(headers, "user-agent")) try writer.writeAll("user-agent: eyg-zig/0.1\r\n");
    if (!hasHeader(headers, "connection")) try writer.writeAll("connection: close\r\n");
    if (!hasHeader(headers, "accept-encoding")) try writer.writeAll("accept-encoding: gzip, deflate\r\n");
    for (headers) |header| try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
    if (conn.proxied) {
        const proxy = if (conn.protocol == .tls) req.client.https_proxy else req.client.http_proxy;
        if (proxy) |configured| if (configured.authorization) |authorization| try writer.print("proxy-authorization: {s}\r\n", .{authorization});
    }
    try writer.writeAll("\r\n");
    try conn.flush();
}

fn responseValue(engine: *Engine, req: *std.http.Client.Request) !V {
    const a = engine.allocator;
    // Fetch exposes a decompressed byte body and the original response headers.
    const body = if (req.method == .TRACE) @as([]const u8, "") else try req.reader().readAllAlloc(a, maximum_body);
    var headers = std.ArrayList(std.http.Header).init(a);
    var iter = req.response.iterateHeaders();
    while (iter.next()) |header| {
        if (iter.is_trailer) break;
        const name = try std.ascii.allocLowerString(a, header.name);
        const header_value = try fromLatin1(a, header.value);
        var merged = false;
        if (!std.mem.eql(u8, name, "set-cookie")) {
            for (headers.items) |*previous| {
                if (std.mem.eql(u8, previous.name, name)) {
                    previous.value = header_value;
                    merged = true;
                    break;
                }
            }
        }
        if (!merged) try headers.append(.{ .name = name, .value = header_value });
    }
    // The pinned Gleam/Bun transport lowercases names, keeps the last
    // ordinary repeated response field, and appends Set-Cookie fields after
    // lexically sorted ordinary headers. Its behavior is the oracle here.
    std.mem.sort(std.http.Header, headers.items, {}, struct {
        fn less(_: void, lhs: std.http.Header, rhs: std.http.Header) bool {
            const left_cookie = std.mem.eql(u8, lhs.name, "set-cookie");
            const right_cookie = std.mem.eql(u8, rhs.name, "set-cookie");
            if (left_cookie != right_cookie) return !left_cookie;
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    }.less);
    var result: V = .{ .list = null };
    var i = headers.items.len;
    while (i > 0) {
        i -= 1;
        const header = headers.items[i];
        const value = try record(a, &.{ .{ .name = "key", .value = .{ .string = header.name } }, .{ .name = "value", .value = .{ .string = header.value } } });
        result = try engine.cons(value, result.list);
    }
    return record(a, &.{ .{ .name = "status", .value = .{ .integer = @intFromEnum(req.response.status) } }, .{ .name = "headers", .value = result }, .{ .name = "body", .value = .{ .binary = body } } });
}

fn requestUri(a: A, lift: V) !std.Uri {
    const scheme = try field(lift, "scheme");
    if (scheme != .tagged) return error.InvalidFetchScheme;
    const scheme_text = if (std.mem.eql(u8, scheme.tagged.label, "HTTP")) "http" else if (std.mem.eql(u8, scheme.tagged.label, "HTTPS")) "https" else return error.InvalidFetchScheme;
    const host = try string(try field(lift, "host"));
    if (host.len == 0 or std.mem.indexOfAny(u8, host, "/@?#\r\n\x00 ") != null) return error.InvalidFetchHost;
    const port_value = try option(try field(lift, "port"));
    const port: ?u16 = if (port_value) |value| blk: {
        if (value != .integer or value.integer < 0 or value.integer > 65535) return error.InvalidFetchPort;
        break :blk @intCast(value.integer);
    } else null;
    const path = try string(try field(lift, "path"));
    const query_value = try option(try field(lift, "query"));
    const query = if (query_value) |value| try string(value) else null;
    var url = std.ArrayList(u8).init(a);
    try url.writer().print("{s}://{s}", .{ scheme_text, host });
    if (port) |number| try url.writer().print(":{d}", .{number});
    if (path.len == 0 or path[0] != '/') try url.append('/');
    try appendUrlText(&url, path);
    if (query) |value| {
        try url.append('?');
        try appendUrlText(&url, value);
    }
    const uri = try std.Uri.parse(url.items);
    if (uri.user != null or uri.password != null) return error.UrlCredentialsForbidden;
    return uri;
}

fn appendUrlText(output: *std.ArrayList(u8), text: []const u8) !void {
    // Keep existing percent escapes and URL delimiters. Encode UTF-8 bytes and
    // characters the fetch URL constructor percent-encodes in paths/queries.
    for (text) |byte| {
        if (byte <= 0x20 or byte >= 0x7f or byte == '"' or byte == '<' or byte == '>' or byte == '`') try output.writer().print("%{X:0>2}", .{byte}) else try output.append(byte);
    }
}

fn methodName(a: A, value: V) ![]const u8 {
    if (value != .tagged) return error.InvalidFetchMethod;
    const name = if (std.mem.eql(u8, value.tagged.label, "OTHER")) try string(value.tagged.value) else value.tagged.label;
    const method = try std.ascii.allocUpperString(a, name);
    // The pinned Bun Request constructor recognizes this method set. Other
    // strings (including valid extension tokens) become GET before transport.
    const known = std.StaticStringMap(void).initComptime(.{
        .{ "ACL", {} },        .{ "BIND", {} },        .{ "CHECKOUT", {} },
        .{ "CONNECT", {} },    .{ "COPY", {} },        .{ "DELETE", {} },
        .{ "GET", {} },        .{ "HEAD", {} },        .{ "LINK", {} },
        .{ "LOCK", {} },       .{ "M-SEARCH", {} },    .{ "MERGE", {} },
        .{ "MKACTIVITY", {} }, .{ "MKCALENDAR", {} },  .{ "MKCOL", {} },
        .{ "MOVE", {} },       .{ "NOTIFY", {} },      .{ "OPTIONS", {} },
        .{ "PATCH", {} },      .{ "POST", {} },        .{ "PROPFIND", {} },
        .{ "PROPPATCH", {} },  .{ "PURGE", {} },       .{ "PUT", {} },
        .{ "QUERY", {} },      .{ "REBIND", {} },      .{ "REPORT", {} },
        .{ "SEARCH", {} },     .{ "SOURCE", {} },      .{ "SUBSCRIBE", {} },
        .{ "TRACE", {} },      .{ "UNBIND", {} },      .{ "UNLINK", {} },
        .{ "UNLOCK", {} },     .{ "UNSUBSCRIBE", {} },
    });
    return if (known.has(method)) method else "GET";
}

fn requestHeaders(a: A, value: V) !std.ArrayList(std.http.Header) {
    if (value != .list) return error.InvalidFetchHeaders;
    var headers = std.ArrayList(std.http.Header).init(a);
    var cursor = value.list;
    var bytes: usize = 0;
    while (cursor) |cell| : (cursor = cell.tail) {
        const name = try std.ascii.allocLowerString(a, try string(try field(cell.head, "key")));
        const content = try headerText(std.mem.trim(u8, try string(try field(cell.head, "value")), " \t"));
        if (name.len == 0) return error.InvalidFetchHeader;
        for (name) |byte| if (!tokenByte(byte)) return error.InvalidFetchHeader;
        if (std.mem.indexOfAny(u8, content, "\r\n\x00") != null) return error.InvalidFetchHeader;
        bytes += name.len + content.len + 4;
        if (bytes > maximum_headers) return error.HttpHeadersOversize;
        // Framing belongs to the native transport; destination credentials may
        // never masquerade as configured proxy credentials.
        if (std.mem.eql(u8, name, "content-length") or std.mem.eql(u8, name, "transfer-encoding") or std.mem.eql(u8, name, "proxy-authorization")) continue;
        var merged = false;
        for (headers.items) |*previous| if (std.mem.eql(u8, previous.name, name)) {
            previous.value = try std.fmt.allocPrint(a, "{s}, {s}", .{ previous.value, content });
            merged = true;
            break;
        };
        if (!merged) try headers.append(.{ .name = name, .value = content });
    }
    return headers;
}
fn headerText(input: []const u8) ![]const u8 {
    const decoded = std.unicode.Utf8View.init(input) catch return error.InvalidFetchHeader;
    var iter = decoded.iterator();
    while (iter.nextCodepoint()) |point| if (point > 255) return error.InvalidFetchHeader;
    // The pinned Bun Headers accepts ByteString code points but sends their
    // UTF-8 representation. Preserve that observable wire behavior.
    return input;
}

fn fromLatin1(a: A, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(a);
    for (input) |byte| {
        var encoded: [4]u8 = undefined;
        const size = try std.unicode.utf8Encode(byte, &encoded);
        try result.appendSlice(encoded[0..size]);
    }
    return result.toOwnedSlice();
}

fn stripSensitive(headers: *std.ArrayList(std.http.Header)) void {
    var i: usize = 0;
    while (i < headers.items.len) {
        const name = headers.items[i].name;
        if (std.mem.eql(u8, name, "authorization") or std.mem.eql(u8, name, "cookie") or std.mem.eql(u8, name, "cookie2") or std.mem.eql(u8, name, "proxy-authorization") or std.mem.eql(u8, name, "host")) {
            _ = headers.orderedRemove(i);
        } else i += 1;
    }
}
fn stripBodyHeaders(headers: *std.ArrayList(std.http.Header)) void {
    var i: usize = 0;
    while (i < headers.items.len) {
        const name = headers.items[i].name;
        if (std.mem.eql(u8, name, "content-type") or std.mem.eql(u8, name, "content-language") or std.mem.eql(u8, name, "content-location") or std.mem.eql(u8, name, "content-encoding")) {
            _ = headers.orderedRemove(i);
        } else i += 1;
    }
}
fn sameOrigin(lhs: std.Uri, rhs: std.Uri, a: A) bool {
    const left = (lhs.host orelse return false).toRawMaybeAlloc(a) catch return false;
    const right = (rhs.host orelse return false).toRawMaybeAlloc(a) catch return false;
    const lp = lhs.port orelse if (std.ascii.eqlIgnoreCase(lhs.scheme, "https")) @as(u16, 443) else 80;
    const rp = rhs.port orelse if (std.ascii.eqlIgnoreCase(rhs.scheme, "https")) @as(u16, 443) else 80;
    return std.ascii.eqlIgnoreCase(lhs.scheme, rhs.scheme) and std.ascii.eqlIgnoreCase(left, right) and lp == rp;
}
fn isRedirect(code: u16) bool {
    return code == 301 or code == 302 or code == 303 or code == 307 or code == 308;
}
fn hasHeader(headers: []const std.http.Header, name: []const u8) bool {
    for (headers) |header| if (std.mem.eql(u8, header.name, name)) return true;
    return false;
}
fn tokenByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", byte) != null;
}
fn componentBytes(value: std.Uri.Component) []const u8 {
    return switch (value) {
        .raw, .percent_encoded => |bytes| bytes,
    };
}
fn field(value: V, name: []const u8) !V {
    if (value == .record) for (value.record) |item| {
        if (std.mem.eql(u8, item.name, name)) return item.value;
    };
    return error.InvalidFetchRequest;
}
fn string(value: V) ![]const u8 {
    return if (value == .string) value.string else error.InvalidFetchRequest;
}
fn option(value: V) !?V {
    if (value != .tagged) return error.InvalidFetchOption;
    if (std.mem.eql(u8, value.tagged.label, "None")) return null;
    if (std.mem.eql(u8, value.tagged.label, "Some")) return value.tagged.value;
    return error.InvalidFetchOption;
}
fn record(a: A, fields: []const interpreter.Field) !V {
    return .{ .record = try a.dupe(interpreter.Field, fields) };
}
fn environment(a: A, names: []const []const u8) !?[]const u8 {
    for (names) |name| {
        const value = std.process.getEnvVarOwned(a, name) catch |err| {
            if (err == error.EnvironmentVariableNotFound) continue;
            return err;
        };
        return value;
    }
    return null;
}

fn configureTrust(client: *std.http.Client, a: A) !void {
    if (builtin.abi == .android) {
        // Android 14+ moves roots into the updatable Conscrypt APEX. Scan
        // both locations: older releases use only the system directory.
        for ([_][]const u8{ "/apex/com.android.conscrypt/cacerts", "/system/etc/security/cacerts" }) |path| {
            addCertificatesFromDirectory(&client.ca_bundle, a, path) catch |err| switch (err) {
                error.FileNotFound, error.NotDir, error.AccessDenied => continue,
                else => return err,
            };
        }
    } else try client.ca_bundle.rescan(a);
    for ([_][]const u8{ "SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS" }) |name| {
        const path = (try environment(a, &.{name})) orelse continue;
        if (path.len == 0) continue;
        try client.ca_bundle.addCertsFromFilePath(a, std.fs.cwd(), path);
    }
    if (try environment(a, &.{"SSL_CERT_DIR"})) |paths| {
        var directories = std.mem.splitScalar(u8, paths, std.fs.path.delimiter);
        while (directories.next()) |path| if (path.len != 0) try addCertificatesFromDirectory(&client.ca_bundle, a, path);
    }
    if (client.ca_bundle.map.count() == 0) return error.CertificateAuthorityUnavailable;
    client.next_https_rescan_certs = false;
}

/// Load an OS trust directory without relying on filename extensions. Android
/// uses hashed names (for example 0123abcd.0); PEM and single DER certificates
/// are both accepted. The trust decision remains the caller's choice of store.
pub fn addCertificatesFromDirectory(bundle: *std.crypto.Certificate.Bundle, a: A, path: []const u8) !void {
    var directory = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer directory.close();
    var iter = directory.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        var file = try directory.openFile(entry.name, .{});
        defer file.close();
        const bytes = try file.readToEndAlloc(a, 1024 * 1024);
        defer a.free(bytes);
        if (std.mem.indexOf(u8, bytes, "-----BEGIN CERTIFICATE-----") != null) {
            try file.seekTo(0);
            try bundle.addCertsFromFile(a, file);
        } else if (bytes.len > 0 and bytes[0] == 0x30) {
            const start = std.math.cast(u32, bundle.bytes.items.len) orelse return error.CertificateAuthorityBundleTooBig;
            try bundle.bytes.appendSlice(a, bytes);
            errdefer bundle.bytes.items.len = start;
            try bundle.parseCert(a, start, std.time.timestamp());
        }
    }
}

/// std.http 0.14 loads proxy variables but has no NO_PROXY support. Respect
/// explicit configured exclusions per redirect hop; never bypass automatically.
fn noProxyMatches(exclusions: []const u8, host: []const u8, port: u16) bool {
    const target = std.mem.trim(u8, host, "[]");
    var entries = std.mem.splitScalar(u8, exclusions, ',');
    while (entries.next()) |raw| {
        var entry = std.mem.trim(u8, raw, " \t");
        if (entry.len == 0) continue;
        if (std.mem.eql(u8, entry, "*")) return true;
        if (entry[0] == '[') {
            const close = std.mem.indexOfScalar(u8, entry, ']') orelse continue;
            if (close + 1 < entry.len) {
                if (entry[close + 1] != ':') continue;
                const requested = std.fmt.parseInt(u16, entry[close + 2 ..], 10) catch continue;
                if (requested != port) continue;
            }
            entry = entry[1..close];
        } else if (std.mem.indexOfScalar(u8, entry, ':')) |colon| {
            if (std.mem.lastIndexOfScalar(u8, entry, ':').? == colon) {
                const requested = std.fmt.parseInt(u16, entry[colon + 1 ..], 10) catch continue;
                if (requested != port) continue;
                entry = entry[0..colon];
            }
        }
        if (std.mem.startsWith(u8, entry, "*.")) entry = entry[2..] else if (std.mem.startsWith(u8, entry, ".")) entry = entry[1..];
        if (std.ascii.eqlIgnoreCase(target, entry)) return true;
        if (target.len > entry.len and target[target.len - entry.len - 1] == '.' and std.ascii.endsWithIgnoreCase(target, entry)) return true;
    }
    return false;
}

test "configured proxy exclusions are exact or domain-boundary matches" {
    try std.testing.expect(noProxyMatches("localhost,127.0.0.1,::1", "127.0.0.1", 8080));
    try std.testing.expect(noProxyMatches("[::1]:8443", "[::1]", 8443));
    try std.testing.expect(!noProxyMatches("[::1]:8443", "::1", 443));
    try std.testing.expect(noProxyMatches(".example.test:80", "api.example.test", 80));
    try std.testing.expect(!noProxyMatches(".example.test:80", "badexample.test", 80));
    try std.testing.expect(!noProxyMatches("", "127.0.0.1", 80));
}
