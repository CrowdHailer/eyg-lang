//! EYG surface syntax to canonical DAG-JSON IR. All storage belongs to the caller.
const std = @import("std");
const unicode = @import("unicode.zig");
const codec = @import("ir_codec.zig");
const A = std.mem.Allocator;
const J = std.json.Value;
const Span = @import("inspection.zig").Span;

pub const ParseError = error{ InvalidSyntax, IntegerOutOfRange, OutOfMemory };
const Kind = enum { name, upper, integer, string, lparen, rparen, lbrace, rbrace, lsquare, rsquare, comma, colon, dot, spread, arrow, equal, bang, hash, at, bar, minus, invalid, unterminated, invalid_escape, eof };
const Token = struct { kind: Kind, text: []const u8, at: usize };
const Pattern = struct { name: ?[]const u8 = null, fields: []const Field = &.{} };
const Field = struct { name: []const u8, value: J, span: Span = .{ 0, 0 }, colon: ?Span = null, from: usize = 0 };

pub fn object(a: A, fields: []const struct { []const u8, J }) !J {
    var obj = std.json.ObjectMap.init(a);
    for (fields) |pair| try obj.put(pair[0], pair[1]);
    return .{ .object = obj };
}
pub fn node(a: A, code: []const u8) !J {
    return object(a, &.{.{ "0", .{ .string = code } }});
}
pub fn label(a: A, code: []const u8, name: []const u8) !J {
    return object(a, &.{ .{ "0", .{ .string = code } }, .{ "l", .{ .string = name } } });
}
pub fn literal(a: A, code: []const u8, value: J) !J {
    return object(a, &.{ .{ "0", .{ .string = code } }, .{ "v", value } });
}
pub fn apply(a: A, f: J, arg: J) !J {
    return object(a, &.{ .{ "0", .{ .string = "a" } }, .{ "f", f }, .{ "a", arg } });
}
pub fn lambda(a: A, name: []const u8, body: J) !J {
    return object(a, &.{ .{ "0", .{ .string = "f" } }, .{ "l", .{ .string = name } }, .{ "b", body } });
}
pub fn letNode(a: A, name: []const u8, value: J, body: J) !J {
    return object(a, &.{ .{ "0", .{ .string = "l" } }, .{ "l", .{ .string = name } }, .{ "v", value }, .{ "t", body } });
}

pub fn parse(a: A, source: []const u8) ParseError!J {
    var p: Parser = .{ .a = a, .tokens = try lex(a, source) };
    const result = try p.block();
    if (p.peek().kind != .eof) return error.InvalidSyntax;
    return result;
}

pub fn parseExpression(a: A, source: []const u8) ParseError!J {
    var p: Parser = .{ .a = a, .tokens = try lex(a, source) };
    const result = try p.expression();
    if (p.peek().kind != .eof) return error.InvalidSyntax;
    return result;
}

/// The same parser with optional source offsets for imported module diagnostics.
/// Public DAG-JSON parsing and hashing keep using the unannotated entry points.
pub fn parseExpressionLocated(a: A, source: []const u8) ParseError!J {
    var p: Parser = .{ .a = a, .tokens = try lex(a, source), .located = true };
    const result = try p.expression();
    if (p.peek().kind != .eof) return error.InvalidSyntax;
    return result;
}

const Diagnostic = struct { kind: enum { unexpected, end, trailing, equals, arrow, unclosed, effect, builtin, cid, version, import_path, invalid, unterminated, escape, integer }, at: ?usize, token: []const u8 = "" };

/// The oracle's diagnostic text is part of the TUI buffer contract.
pub fn diagnostic(a: A, source: []const u8) ![]const u8 {
    var p: Parser = .{ .a = a, .tokens = try lex(a, source) };
    if (p.expression()) |_| {} else |_| {}
    const d = p.failure orelse Diagnostic{ .kind = .trailing, .at = p.peek().at, .token = p.peek().text };
    const description = switch (d.kind) {
        .end => try a.dupe(u8, "unexpected end of input"),
        .unexpected => try std.fmt.allocPrint(a, "unexpected `{s}` at position {d}", .{ d.token, d.at.? }),
        .trailing => try std.fmt.allocPrint(a, "unexpected `{s}` at position {d} — the expression is complete but there are leftover tokens", .{ d.token, d.at.? }),
        .equals => try std.fmt.allocPrint(a, "expected `=` after let binding name at position {d}", .{d.at.?}),
        .arrow => try std.fmt.allocPrint(a, "expected `->` followed by `{{` in function definition at position {d}", .{d.at.?}),
        .unclosed => try std.fmt.allocPrint(a, "unclosed function body — expected `}}` to close the `{{` opened at position {d}", .{d.at.?}),
        .effect => try std.fmt.allocPrint(a, "expected an uppercase effect name after `{s}` at position {d}", .{ d.token, d.at.? }),
        .builtin => try std.fmt.allocPrint(a, "expected a builtin identifier after `!` at position {d}", .{d.at.?}),
        .cid => try std.fmt.allocPrint(a, "invalid content identifier (CID) at position {d}", .{d.at.?}),
        .version => try std.fmt.allocPrint(a, "expected an integer release version after `:` at position {d}", .{d.at.?}),
        .import_path => try std.fmt.allocPrint(a, "expected a string path after `import` at position {d}", .{d.at.?}),
        .invalid => try std.fmt.allocPrint(a, "invalid character '{s}' at position {d}", .{ d.token, d.at.? }),
        .unterminated => try std.fmt.allocPrint(a, "unterminated string literal at position {d}", .{d.at.?}),
        .escape => try std.fmt.allocPrint(a, "invalid escape sequence `\\{s}` in string at position {d}", .{ d.token, d.at.? }),
        .integer => try std.fmt.allocPrint(a, "integer literal `{s}` is out of range at position {d}", .{ d.token, d.at.? }),
    };
    const hint = switch (d.kind) {
        .end => "program must end with valid expression",
        .unexpected => "view the syntax guide",
        .trailing => if (std.mem.eql(u8, d.token, "let")) "the previous expression already completed the block. If you meant the block to continue, bind that expression to `let _ = ...` first." else "EYG uses function calls for operations (e.g. !int_add(a, b)), not infix operators",
        .equals => "let bindings use the form `let name = expression`, names are lower snake_case such as `star_count`",
        .arrow => "functions are written as `(arg) -> { body }`",
        .unclosed => "every `{` in a function body must be closed with `}`",
        .effect => try std.fmt.allocPrint(a, "effect names must start with an uppercase letter, e.g. `{s} Log`", .{d.token}),
        .builtin => "builtins use lowercase names, e.g. `!int_add`",
        .cid => "CID references use a valid base32-encoded CID, e.g. `#bafyreig...`",
        .version => "pin a release with `@package:N` (e.g. `@tandard:3`) or omit `:` to track the latest",
        .import_path => "import paths must be string literals, e.g. `import \"./module.eyg.json\"`",
        .invalid => "remove or replace this character — EYG does not use it",
        .unterminated => "close the string with a double-quote `\"`",
        .escape => "valid escapes are \\n (newline), \\t (tab), \\r (carriage return), \\\" (quote), \\\\ (backslash)",
        .integer => "on the JavaScript target integers must be within the safe range (-(2^53-1) to 2^53-1)",
    };
    const prefix = try std.fmt.allocPrint(a, "error: {s}\nhint: {s}", .{ description, hint });
    const position = d.at orelse return prefix;
    var line_num: usize = 1;
    var start: usize = 0;
    while (start <= source.len) {
        var end = start;
        while (end < source.len and source[end] != '\r' and source[end] != '\n') : (end += 1) {}
        if (position <= end) {
            const gutter = try std.fmt.allocPrint(a, " {d} | ", .{line_num});
            const spaces = try a.alloc(u8, gutter.len + position - start);
            @memset(spaces, ' ');
            return std.fmt.allocPrint(a, "{s}\n\n{s}{s}\n{s}^", .{ prefix, gutter, source[start..end], spaces });
        }
        if (end == source.len) break;
        start = end + (if (source[end] == '\r' and end + 1 < source.len and source[end + 1] == '\n') @as(usize, 2) else 1);
        line_num += 1;
    }
    return prefix;
}

fn lex(a: A, source: []const u8) ParseError![]const Token {
    var tokens = std.ArrayList(Token).init(a);
    var i: usize = 0;
    while (i < source.len) {
        const at = i;
        const c = source[i];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            i += 1;
            continue;
        }
        if (c == '/' and i + 1 < source.len and source[i + 1] == '/') {
            while (i < source.len and source[i] != '\n') : (i += 1) {}
            continue;
        }
        if (std.ascii.isAlphabetic(c) or c == '_') {
            i += 1;
            while (i < source.len and (std.ascii.isLower(source[i]) or (std.ascii.isUpper(c) and std.ascii.isUpper(source[i])) or std.ascii.isDigit(source[i]) or source[i] == '_')) : (i += 1) {}
            try tokens.append(.{ .kind = if (std.ascii.isUpper(c)) .upper else .name, .text = source[at..i], .at = at });
            continue;
        }
        if (std.ascii.isDigit(c)) {
            i += 1;
            while (i < source.len and std.ascii.isDigit(source[i])) : (i += 1) {}
            try tokens.append(.{ .kind = .integer, .text = source[at..i], .at = at });
            continue;
        }
        if (c == '"') {
            i += 1;
            var text = std.ArrayList(u8).init(a);
            var bad_escape: ?Token = null;
            while (i < source.len and source[i] != '"') {
                if (source[i] == '\\') {
                    i += 1;
                    if (i >= source.len) break;
                    try text.append(switch (source[i]) {
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        '"' => '"',
                        '\\' => '\\',
                        else => blk: {
                            if (bad_escape == null) {
                                const raw = try std.mem.concat(a, u8, &.{ text.items, source[i - 1 ..] });
                                const first_end = unicode.graphemeEnd(raw, 0);
                                const second_end = unicode.graphemeEnd(raw, first_end);
                                bad_escape = .{ .kind = .invalid_escape, .text = raw[first_end..second_end], .at = at };
                            }
                            break :blk source[i];
                        },
                    });
                } else try text.append(source[i]);
                i += 1;
            }
            if (i == source.len) {
                try tokens.append(.{ .kind = .unterminated, .text = source[at..], .at = at });
                break;
            }
            i += 1;
            try tokens.append(bad_escape orelse .{ .kind = .string, .text = try text.toOwnedSlice(), .at = at });
            continue;
        }
        i += 1;
        const kind: Kind = switch (c) {
            '(' => .lparen,
            ')' => .rparen,
            '{' => .lbrace,
            '}' => .rbrace,
            '[' => .lsquare,
            ']' => .rsquare,
            ',' => .comma,
            ':' => .colon,
            '=' => .equal,
            '!' => .bang,
            '#' => .hash,
            '@' => .at,
            '|' => .bar,
            '.' => blk: {
                if (i < source.len and source[i] == '.') {
                    i += 1;
                    break :blk .spread;
                }
                break :blk .dot;
            },
            '-' => blk: {
                if (i < source.len and source[i] == '>') {
                    i += 1;
                    break :blk .arrow;
                }
                break :blk .minus;
            },
            else => .invalid,
        };
        if (kind == .invalid and c >= 128) i = unicode.graphemeEnd(source, at);
        try tokens.append(.{ .kind = kind, .text = source[at..i], .at = at });
    }
    try tokens.append(.{ .kind = .eof, .text = "", .at = source.len });
    return tokens.toOwnedSlice();
}

const Parser = struct {
    a: A,
    tokens: []const Token,
    pos: usize = 0,
    failure: ?Diagnostic = null,
    located: bool = false,
    fn withSpan(p: *Parser, ir: J, start: usize, end: usize) ParseError!J {
        if (!p.located) return ir;
        var result = ir;
        var offsets = std.ArrayList(J).init(p.a);
        try offsets.appendSlice(&.{ .{ .integer = @intCast(start) }, .{ .integer = @intCast(end) } });
        try result.object.put("_span", .{ .array = offsets });
        return result;
    }
    fn range(_: *Parser, ir: J) Span {
        return @import("inspection.zig").span(ir);
    }
    fn peek(p: *Parser) Token {
        return p.tokens[p.pos];
    }
    fn take(p: *Parser) Token {
        const t = p.peek();
        if (t.kind != .eof) p.pos += 1;
        return t;
    }
    fn accept(p: *Parser, kind: Kind) bool {
        if (p.peek().kind != kind) return false;
        _ = p.take();
        return true;
    }
    fn fail(p: *Parser, kind: @FieldType(Diagnostic, "kind"), at: ?usize, token: []const u8) ParseError {
        if (p.failure == null) p.failure = .{ .kind = kind, .at = at, .token = token };
        return error.InvalidSyntax;
    }
    fn unexpected(p: *Parser, t: Token) ParseError {
        return p.fail(if (t.kind == .eof) .end else .unexpected, if (t.kind == .eof) null else t.at, t.text);
    }
    fn expect(p: *Parser, kind: Kind) ParseError!Token {
        const t = p.take();
        if (t.kind != kind or (kind == .name and reserved(t.text))) return p.unexpected(t);
        return t;
    }
    fn word(p: *Parser, s: []const u8) bool {
        return p.peek().kind == .name and std.mem.eql(u8, p.peek().text, s);
    }

    fn pattern(p: *Parser) ParseError!Pattern {
        if (p.peek().kind == .name and !reserved(p.peek().text)) return .{ .name = p.take().text };
        _ = try p.expect(.lbrace);
        var fields = std.ArrayList(Field).init(p.a);
        while (!p.accept(.rbrace)) {
            const field = try p.expect(.name);
            const colon: ?Span = if (p.peek().kind == .colon) blk: {
                const at_ = p.take().at;
                break :blk .{ at_, at_ + 1 };
            } else null;
            const name = if (colon != null) (try p.expect(.name)).text else field.text;
            try fields.append(.{ .name = field.text, .value = .{ .string = name }, .span = .{ field.at, field.at + field.text.len }, .colon = colon });
            if (p.accept(.rbrace)) break;
            _ = try p.expect(.comma);
        }
        return .{ .fields = try fields.toOwnedSlice() };
    }
    fn destructure(p: *Parser, pattern_: Pattern, body_: J) ParseError!J {
        var body = body_;
        var n = pattern_.fields.len;
        while (n > 0) {
            n -= 1;
            const f = pattern_.fields[n];
            const colon = f.colon orelse f.span;
            const select = try p.withSpan(try label(p.a, "g", f.name), f.span[0], f.span[1]);
            const variable = try p.withSpan(try label(p.a, "v", "$"), colon[0], colon[1]);
            const value = try p.withSpan(try apply(p.a, select, variable), f.span[0], colon[1]);
            body = try p.withSpan(try letNode(p.a, f.value.string, value, body), f.span[0], p.range(body_)[1]);
        }
        return body;
    }
    fn bindPattern(p: *Parser, pat: Pattern, value: J, body: J, start: usize, end: usize) ParseError!J {
        return p.withSpan(try letNode(p.a, pat.name orelse "$", value, if (pat.name == null) try p.destructure(pat, body) else body), start, end);
    }
    fn block(p: *Parser) ParseError!J {
        if (p.word("let")) {
            const start = p.take().at;
            const pat = try p.pattern();
            if (!p.accept(.equal)) return if (p.peek().kind == .eof) p.unexpected(p.peek()) else p.fail(.equals, p.peek().at, "");
            const value = try p.expression();
            const body = if (p.peek().kind == .eof or p.peek().kind == .rbrace) try node(p.a, "z") else try p.block();
            return p.bindPattern(pat, value, body, start, p.range(body)[1]);
        }
        return p.expression();
    }
    fn expression(p: *Parser) ParseError!J {
        var value = try p.atom();
        while (true) {
            if (p.accept(.lparen)) {
                if (p.peek().kind == .rparen) return error.InvalidSyntax;
                while (true) {
                    const argument = try p.expression();
                    value = try p.withSpan(try apply(p.a, value, argument), p.range(value)[0], p.range(argument)[1] + 1);
                    if (p.accept(.rparen)) break;
                    _ = try p.expect(.comma);
                }
            } else if (p.peek().kind == .dot) {
                const dot = p.take().at;
                const field = try p.expect(.name);
                value = try p.withSpan(try apply(p.a, try p.withSpan(try label(p.a, "g", field.text), dot, field.at + field.text.len), value), p.range(value)[0], field.at + field.text.len);
            } else break;
        }
        return value;
    }
    fn atom(p: *Parser) ParseError!J {
        const t = p.take();
        switch (t.kind) {
            .integer, .minus => {
                const raw = if (t.kind == .minus) (try p.expect(.integer)).text else t.text;
                var n = std.fmt.parseInt(i64, raw, 10) catch {
                    p.failure = .{ .kind = .integer, .at = t.at, .token = raw };
                    return error.IntegerOutOfRange;
                };
                if (t.kind == .minus) n = -n;
                if (n > 9007199254740991 or n < -9007199254740991) {
                    p.failure = .{ .kind = .integer, .at = if (t.kind == .minus) t.at + 1 else t.at, .token = raw };
                    return error.IntegerOutOfRange;
                }
                const end = if (t.kind == .minus) p.tokens[p.pos - 1].at + raw.len else t.at + raw.len;
                return p.withSpan(try literal(p.a, "i", .{ .integer = n }), t.at, end);
            },
            .string => return p.withSpan(try literal(p.a, "s", .{ .string = t.text }), t.at, t.at + t.text.len + 2),
            .upper => return p.withSpan(try label(p.a, "t", t.text), t.at, t.at + t.text.len),
            .bang => {
                if (p.peek().kind != .name or reserved(p.peek().text)) return p.fail(.builtin, p.peek().at, "");
                const name = p.take();
                return p.withSpan(try label(p.a, "b", name.text), t.at, name.at + name.text.len);
            },
            .hash => {
                if (p.peek().kind != .name or !validCid(p.peek().text)) return p.fail(.cid, p.peek().at, "");
                const name = p.take();
                const cid = try canonicalCid(p.a, name.text);
                return p.withSpan(try object(p.a, &.{ .{ "0", .{ .string = "#" } }, .{ "l", try object(p.a, &.{.{ "/", .{ .string = cid } }}) } }), t.at, name.at + name.text.len);
            },
            .at => {
                var result = try object(p.a, &.{ .{ "0", .{ .string = "@" } }, .{ "p", .{ .string = (try p.expect(.name)).text } } });
                if (p.accept(.colon)) {
                    if (p.peek().kind != .integer) return p.fail(.version, p.peek().at, "");
                    const version_token = p.take();
                    const version = std.fmt.parseInt(i64, version_token.text, 10) catch return p.fail(.version, version_token.at, "");
                    if (version <= 0) return p.fail(.version, version_token.at, "");
                    try result.object.put("r", .{ .integer = version });
                    if (p.accept(.colon)) {
                        if (p.peek().kind != .name or !validCid(p.peek().text)) return p.fail(.cid, p.peek().at, "");
                        const cid = try canonicalCid(p.a, p.take().text);
                        try result.object.put("l", try object(p.a, &.{.{ "/", .{ .string = cid } }}));
                    }
                }
                const last = p.tokens[p.pos - 1];
                return p.withSpan(result, t.at, last.at + last.text.len);
            },
            .lparen => {
                var patterns = std.ArrayList(Pattern).init(p.a);
                try patterns.append(try p.pattern());
                while (p.accept(.comma)) try patterns.append(try p.pattern());
                _ = try p.expect(.rparen);
                if (!p.accept(.arrow)) return if (p.peek().kind == .eof) p.unexpected(p.peek()) else p.fail(.arrow, p.peek().at, "");
                if (p.peek().kind != .lbrace) return p.fail(.arrow, p.peek().at, "");
                const brace_at = p.take().at;
                var body = try p.expression();
                if (p.peek().kind != .rbrace) return p.fail(.unclosed, brace_at, "");
                const end = p.take().at + 1;
                var n = patterns.items.len;
                while (n > 0) {
                    n -= 1;
                    const pat = patterns.items[n];
                    body = try p.withSpan(try lambda(p.a, pat.name orelse "$", if (pat.name == null) try p.destructure(pat, body) else body), t.at, end);
                }
                return body;
            },
            .lsquare => {
                var items = std.ArrayList(Field).init(p.a);
                var tail = try node(p.a, "ta");
                var from = t.at;
                var finished = false;
                while (p.peek().kind != .rsquare) {
                    // The oracle accepts spread only after at least one item.
                    if (p.peek().kind == .spread) {
                        if (items.items.len == 0) return error.InvalidSyntax;
                        _ = p.take();
                        tail = try p.expression();
                        _ = try p.expect(.rsquare);
                        finished = true;
                        break;
                    }
                    try items.append(.{ .name = "", .value = try p.expression(), .from = from });
                    if (p.peek().kind == .rsquare) break;
                    from = (try p.expect(.comma)).at;
                }
                if (!finished) {
                    const close = p.take().at;
                    tail = try p.withSpan(tail, if (items.items.len == 0) t.at else if (from != t.at and p.tokens[p.pos - 2].kind == .comma) from else close, close + 1);
                }
                var n = items.items.len;
                while (n > 0) {
                    n -= 1;
                    const item = items.items[n];
                    const cons = try p.withSpan(try node(p.a, "c"), item.from, item.from + 1);
                    const inner = try p.withSpan(try apply(p.a, cons, item.value), item.from, p.range(item.value)[1]);
                    tail = try p.withSpan(try apply(p.a, inner, tail), item.from, p.range(tail)[1]);
                }
                return tail;
            },
            .lbrace => {
                var fields = std.ArrayList(Field).init(p.a);
                var tail = try node(p.a, "u");
                var overwrite = false;
                var from = t.at;
                var finished = false;
                while (p.peek().kind != .rbrace) {
                    if (p.accept(.spread)) {
                        tail = try p.expression();
                        overwrite = true;
                        _ = try p.expect(.rbrace);
                        finished = true;
                        break;
                    }
                    const name = try p.expect(.name);
                    const colon: ?usize = if (p.peek().kind == .colon) p.take().at else null;
                    const val = if (colon != null) try p.expression() else try p.withSpan(try label(p.a, "v", name.text), name.at, name.at + name.text.len);
                    try fields.append(.{ .name = name.text, .value = val, .span = .{ from, if (colon) |at_| at_ + 1 else name.at + name.text.len } });
                    if (p.peek().kind == .rbrace) break;
                    from = (try p.expect(.comma)).at;
                }
                if (!finished) {
                    const close = p.take().at;
                    tail = try p.withSpan(tail, if (fields.items.len == 0) from else close, close + 1);
                }
                var n = fields.items.len;
                while (n > 0) {
                    n -= 1;
                    const field = fields.items[n];
                    const extension = try p.withSpan(try label(p.a, if (overwrite) "o" else "e", field.name), field.span[0], field.span[1]);
                    const inner = try p.withSpan(try apply(p.a, extension, field.value), field.span[0], p.range(field.value)[1]);
                    tail = try p.withSpan(try apply(p.a, inner, tail), field.span[0], p.range(tail)[1]);
                }
                return tail;
            },
            .name => {
                if (std.mem.eql(u8, t.text, "deep")) return p.unexpected(t);
                if (std.mem.eql(u8, t.text, "todo")) return p.withSpan(try node(p.a, "z"), t.at, t.at + 4);
                if (std.mem.eql(u8, t.text, "import")) {
                    if (p.peek().kind != .string) return p.fail(.import_path, p.peek().at, "");
                    const name = p.take();
                    return p.withSpan(try object(p.a, &.{ .{ "0", .{ .string = "." } }, .{ "i", .{ .string = name.text } } }), t.at, name.at + name.text.len + 2);
                }
                if (std.mem.eql(u8, t.text, "perform") or std.mem.eql(u8, t.text, "handle")) {
                    if (p.peek().kind != .upper) return p.fail(.effect, p.peek().at, t.text);
                    const name = p.take();
                    return p.withSpan(try label(p.a, if (t.text[0] == 'p') "p" else "h", name.text), t.at, name.at + name.text.len);
                }
                if (std.mem.eql(u8, t.text, "let")) {
                    const pat = try p.pattern();
                    if (!p.accept(.equal)) return if (p.peek().kind == .eof) p.unexpected(p.peek()) else p.fail(.equals, p.peek().at, "");
                    const val = try p.expression();
                    const body = try p.expression();
                    return p.bindPattern(pat, val, body, t.at, p.range(body)[1]);
                }
                if (std.mem.eql(u8, t.text, "match")) {
                    const subject: ?J = if (p.peek().kind != .lbrace) try p.expression() else null;
                    const brace = try p.expect(.lbrace);
                    var branches = std.ArrayList(Field).init(p.a);
                    var tail = try node(p.a, "n");
                    var from = if (subject == null) t.at else brace.at;
                    var finished = false;
                    while (p.peek().kind != .rbrace) {
                        if (p.accept(.bar)) {
                            tail = try p.expression();
                            _ = try p.expect(.rbrace);
                            finished = true;
                            break;
                        }
                        const tag = try p.expect(.upper);
                        try branches.append(.{ .name = tag.text, .value = try p.expression(), .span = .{ tag.at, tag.at + tag.text.len }, .from = from });
                        from = p.peek().at;
                    }
                    if (!finished) tail = try p.withSpan(tail, from, p.take().at + 1);
                    const end = p.range(tail)[1];
                    var n = branches.items.len;
                    while (n > 0) {
                        n -= 1;
                        const b = branches.items[n];
                        const case_ = try p.withSpan(try label(p.a, "m", b.name), b.span[0], b.span[1]);
                        const inner = try p.withSpan(try apply(p.a, case_, b.value), b.span[0], p.range(b.value)[1]);
                        tail = try p.withSpan(try apply(p.a, inner, tail), b.from, end);
                    }
                    return if (subject) |s| try p.withSpan(try apply(p.a, tail, s), t.at, end) else tail;
                }
                return p.withSpan(try label(p.a, "v", t.text), t.at, t.at + t.text.len);
            },
            .invalid => return p.fail(.invalid, t.at, t.text),
            .unterminated => return p.fail(.unterminated, t.at, ""),
            .invalid_escape => return p.fail(.escape, t.at, t.text),
            else => return p.unexpected(t),
        }
    }
};

fn reserved(text: []const u8) bool {
    for ([_][]const u8{ "let", "match", "perform", "deep", "handle", "import", "todo" }) |word| if (std.mem.eql(u8, text, word)) return true;
    return false;
}

fn validCid(text: []const u8) bool {
    return codec.validCid(text);
}
fn canonicalCid(a: A, text: []const u8) ParseError![]const u8 {
    return codec.canonicalCid(a, text) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidSyntax,
    };
}

test "surface syntax builds curried IR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parse(arena.allocator(), "let {a} = {a: 20}\n!int_add(a, 22)");
    try std.testing.expectEqualStrings("l", result.object.get("0").?.string);
    try std.testing.expectEqualStrings("$", result.object.get("l").?.string);
    _ = try parse(arena.allocator(), "match Ok(42) { Ok(n) -> { n } | (_) -> { 0 } }");
    _ = try parse(arena.allocator(), "let f = (x, {y}) -> { let z = x !int_add(z,y) } f(1, {y: 2})");
    try std.testing.expectError(error.IntegerOutOfRange, parse(arena.allocator(), "9007199254740992"));
    try std.testing.expectError(error.InvalidSyntax, parse(arena.allocator(), "1 + 2"));
}
