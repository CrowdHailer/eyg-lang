//! The reference value printer exposes Gleam's generic inspector for a Resume
//! switch. Reconstruct that public text from native frames; the VM still owns
//! execution and never calls the oracle. Only its fixed builtin table is generated.
const std = @import("std");
const runtime = @import("interpreter.zig");
const order = @import("oracle_order.zig");
const builtins = @import("generated_builtins_inspect.zig");
const codec = @import("ir_codec.zig");
const A = std.mem.Allocator;
const J = std.json.Value;

pub fn head(a: A, captured: *const runtime.Resumption) ![]const u8 {
    var inspector = Inspector{ .allocator = a, .output = std.ArrayList(u8).init(a) };
    try inspector.resumeSwitch(captured);
    return inspector.output.toOwnedSlice();
}

const Inspector = struct {
    allocator: A,
    output: std.ArrayList(u8),
    fn write(self: *Inspector, text: []const u8) !void {
        try self.output.appendSlice(text);
    }
    fn quote(self: *Inspector, text: []const u8) !void {
        try self.write("\"");
        var i: usize = 0;
        while (i < text.len) {
            const size = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const end = @min(text.len, i + size);
            const cp = std.unicode.utf8Decode(text[i..end]) catch 0xfffd;
            switch (cp) {
                '\n' => try self.write("\\n"),
                '\r' => try self.write("\\r"),
                '\t' => try self.write("\\t"),
                12 => try self.write("\\f"),
                '\\' => try self.write("\\\\"),
                '"' => try self.write("\\\""),
                else => if (cp < 32 or (cp > 126 and cp < 160)) try self.output.writer().print("\\u{{{X:0>4}}}", .{cp}) else try self.write(text[i..end]),
            }
            i = end;
        }
        try self.write("\"");
    }
    fn meta(self: *Inspector, metadata: runtime.InspectionMeta) !void {
        switch (metadata) {
            .none => try self.write("Nil"),
            .literal => |text| try self.write(text),
            .located => |location| {
                try self.write("Location(origin: ");
                switch (location.source.origin) {
                    .disk => |path| {
                        try self.write("Disk(path: ");
                        try self.quote(path);
                        try self.write(")");
                    },
                    .content => |text| {
                        try self.write("Content(cid: ");
                        try self.cid(try runtime.object(self.allocator, &.{.{ "/", .{ .string = text } }}));
                        try self.write(")");
                    },
                    .inline_code => try self.write("Inline"),
                    .pipe => try self.write("Pipe"),
                    .repl => try self.write("Repl"),
                }
                try self.write(", source: ");
                if (location.source.code) |code| {
                    try self.write("Text(code: ");
                    try self.quote(code);
                    try self.output.writer().print(", span: #({d}, {d}))", .{ location.span[0], location.span[1] });
                } else try self.write("Json");
                try self.write(")");
            },
        }
    }
    fn binary(self: *Inspector, bytes: []const u8) !void {
        try self.write("<<");
        for (bytes, 0..) |byte, i| {
            if (i > 0) try self.write(", ");
            try self.output.writer().print("{d}", .{byte});
        }
        try self.write(">>");
    }
    fn number(self: *Inspector, value_: runtime.Value) !void {
        switch (value_) {
            .integer => |i| try self.write(try runtime.integerText(self.allocator, i)),
            .javascript_integer => |f| {
                try self.write(try runtime.numberText(self.allocator, f));
                if (!std.math.isFinite(f)) try self.write(".0");
            },
            else => unreachable,
        }
    }
    fn scope(self: *Inspector, first: ?*const runtime.Binding) anyerror!void {
        try self.write("[");
        var cursor = first;
        var index: usize = 0;
        while (cursor) |binding| : (cursor = binding.next) {
            if (index > 0) try self.write(", ");
            index += 1;
            try self.write("#(");
            try self.quote(binding.name);
            try self.write(", ");
            try self.value(binding.value);
            try self.write(")");
        }
        try self.write("]");
    }
    fn env(self: *Inspector, first: ?*const runtime.Binding) anyerror!void {
        try self.write("Env(scope: ");
        try self.scope(first);
        try self.write(", builtins: ");
        try self.write(builtins.builtins);
        try self.write(")");
    }
    fn value(self: *Inspector, value_: runtime.Value) anyerror!void {
        switch (value_) {
            .integer, .javascript_integer => {
                try self.write("Integer(value: ");
                try self.number(value_);
                try self.write(")");
            },
            .string => |s| {
                try self.write("String(value: ");
                try self.quote(s);
                try self.write(")");
            },
            .binary => |b| {
                try self.write("Binary(value: ");
                try self.binary(b);
                try self.write(")");
            },
            .list => |first| {
                try self.write("LinkedList(elements: [");
                var cursor = first;
                var i: usize = 0;
                while (cursor) |cell| : (cursor = cell.tail) {
                    if (i > 0) try self.write(", ");
                    i += 1;
                    try self.value(cell.head);
                }
                try self.write("])");
            },
            .record => |fields| {
                try self.write("Record(fields: dict.from_list([");
                // Generic string.inspect uses dict.fold; the language's
                // dict.to_list prepends and therefore exposes its reverse.
                const ordered = try order.fields(self.allocator, fields);
                var i = ordered.len;
                while (i > 0) {
                    i -= 1;
                    const field = ordered[i];
                    if (i + 1 < ordered.len) try self.write(", ");
                    try self.write("#(");
                    try self.quote(field.name);
                    try self.write(", ");
                    try self.value(field.value);
                    try self.write(")");
                }
                try self.write("]))");
            },
            .tagged => |tag| {
                try self.write("Tagged(label: ");
                try self.quote(tag.label);
                try self.write(", value: ");
                try self.value(tag.value);
                try self.write(")");
            },
            .closure => |closure| {
                try self.write("Closure(param: ");
                try self.quote(closure.param);
                try self.write(", body: ");
                try self.node(closure.body, closure.inspection_meta);
                try self.write(", env: ");
                try self.scope(closure.env);
                try self.write(")");
            },
            .partial => |partial| {
                try self.write("Partial(switch: ");
                try self.switch_(partial.kind, partial.label);
                try self.write(", arguments: [");
                for (partial.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.value(arg);
                }
                try self.write("])");
            },
            .@"resume" => |resume_| {
                try self.write("Partial(switch: ");
                try self.resumeSwitch(resume_);
                try self.write(", arguments: [])");
            },
        }
    }
    fn switch_(self: *Inspector, kind: runtime.Kind, label: []const u8) !void {
        const name = switch (kind) {
            .cons => "Cons",
            .extend => "Extend",
            .overwrite => "Overwrite",
            .select => "Select",
            .tag => "Tag",
            .match => "Match",
            .no_cases => "NoCases",
            .perform => "Perform",
            .handle => "Handle",
            .builtin => "Builtin",
        };
        try self.write(name);
        if (kind == .cons or kind == .no_cases) return;
        try self.write(if (kind == .builtin) "(identifier: " else "(label: ");
        try self.quote(label);
        try self.write(")");
    }
    fn resumeSwitch(self: *Inspector, captured: *const runtime.Resumption) anyerror!void {
        var stack = std.ArrayList(*const runtime.Kont).init(self.allocator);
        var cursor = captured.head;
        while (cursor != captured.stop) {
            const entry = cursor orelse break;
            try stack.append(entry);
            cursor = entry.next;
        }
        try self.write("Resume(#([");
        var i = stack.items.len;
        while (i > 0) {
            i -= 1;
            if (i + 1 < stack.items.len) try self.write(", ");
            try self.write("#(");
            try self.frame(stack.items[i]);
            try self.write(", ");
            try self.meta(stack.items[i].inspection_meta);
            try self.write(")");
        }
        try self.write("], ");
        try self.env(captured.env);
        try self.write("))");
    }
    fn frame(self: *Inspector, frame_: *const runtime.Kont) anyerror!void {
        switch (frame_.action) {
            .argument => |ir| {
                try self.write("Arg(");
                try self.node(ir, frame_.inspection_meta);
            },
            .apply => |value_| {
                try self.write("Apply(");
                try self.value(value_);
            },
            .assign => |binding| {
                try self.write("Assign(");
                try self.quote(binding.name);
                try self.write(", ");
                try self.node(binding.then, frame_.inspection_meta);
            },
            .call_with => |value_| {
                try self.write("CallWith(");
                try self.value(value_);
            },
            .delimit => |handler| {
                try self.write("Delimit(");
                try self.quote(handler.label);
                try self.write(", ");
                try self.value(handler.handler);
            },
            .trace => |arg| {
                try self.write("Trace(");
                try self.value(arg);
            },
        }
        try self.write(", ");
        try self.env(frame_.env);
        if (frame_.action == .delimit) try self.write(", False");
        try self.write(")");
    }
    fn node(self: *Inspector, ir: J, context: runtime.InspectionMeta) anyerror!void {
        const metadata = context.at(ir);
        try self.write("#(");
        try self.expression(ir, metadata);
        try self.write(", ");
        try self.meta(metadata);
        try self.write(")");
    }
    fn cid(self: *Inspector, ir: J) !void {
        // Reuse the codec's Number rounding and accepted aliases before reading
        // canonical bytes. This printer does not implement a second CID decoder.
        const text = runtime.stringField(ir, "/") orelse return error.InvalidIR;
        const canonical = try codec.canonicalCid(self.allocator, text);
        var bytes = std.ArrayList(u8).init(self.allocator);
        var bits: u5 = 0;
        var buffer: u16 = 0;
        for (canonical[1..]) |char| {
            const digit: u16 = if (char >= 'a') char - 'a' else char - '2' + 26;
            buffer = (buffer << 5) | digit;
            bits += 5;
            if (bits >= 8) {
                bits -= 8;
                try bytes.append(@intCast((buffer >> @intCast(bits)) & 255));
                buffer &= (@as(u16, 1) << @intCast(bits)) - 1;
            }
        }
        var at: usize = 0;
        _ = readVarint(bytes.items, &at);
        const content_type = readVarint(bytes.items, &at);
        _ = readVarint(bytes.items, &at);
        const count: usize = @intFromFloat(readVarint(bytes.items, &at));
        try self.write("Cid(content_type: ");
        try self.write(try runtime.numberText(self.allocator, content_type));
        try self.write(", content: Multihash(algorithm: Sha256, digest: ");
        try self.binary(bytes.items[at..][0..count]);
        try self.write("))");
    }
    fn readVarint(bytes: []const u8, at: *usize) f64 {
        var value_: f64 = 0;
        var scale: f64 = 1;
        while (at.* < bytes.len) {
            const byte = bytes[at.*];
            at.* += 1;
            value_ += @as(f64, @floatFromInt(byte & 127)) * scale;
            if (byte < 128) break;
            scale *= 128;
        }
        return value_;
    }
    fn reference(self: *Inspector, ir: J, code: []const u8) !void {
        try self.write("Reference(reference: ");
        if (runtime.eq(code, ".")) {
            try self.write("Relative(location: ");
            try self.quote(runtime.stringField(ir, "i").?);
            try self.write(")");
        } else if (runtime.eq(code, "#")) {
            try self.write("Content(cid: ");
            try self.cid(runtime.field(ir, "l"));
            try self.write(")");
        } else {
            const version = runtime.field(ir, "r");
            const module = runtime.field(ir, "l");
            const pinned = module != .null;
            try self.write(if (pinned) "Pinned(release: Release(package: " else if (version != .null) "Version(package: " else "Package(package: ");
            try self.quote(runtime.stringField(ir, "p").?);
            if (version != .null) {
                try self.write(", version: ");
                try self.write(try runtime.numberText(self.allocator, codec.jsonInteger(version).?));
            }
            if (pinned) {
                try self.write(", module: ");
                try self.cid(module);
                try self.write(")");
            }
            try self.write(")");
        }
        try self.write(")");
    }
    fn expression(self: *Inspector, ir: J, metadata: runtime.InspectionMeta) anyerror!void {
        const code = runtime.stringField(ir, "0") orelse return error.InvalidIR;
        if (runtime.eq(code, "a")) {
            try self.write("Apply(func: ");
            try self.node(runtime.field(ir, "f"), metadata);
            try self.write(", argument: ");
            try self.node(runtime.field(ir, "a"), metadata);
            return self.write(")");
        }
        if (runtime.eq(code, "f")) {
            try self.write("Lambda(label: ");
            try self.quote(runtime.stringField(ir, "l").?);
            try self.write(", body: ");
            try self.node(runtime.field(ir, "b"), metadata);
            return self.write(")");
        }
        if (runtime.eq(code, "l")) {
            try self.write("Let(label: ");
            try self.quote(runtime.stringField(ir, "l").?);
            try self.write(", definition: ");
            try self.node(runtime.field(ir, "v"), metadata);
            try self.write(", body: ");
            try self.node(runtime.field(ir, "t"), metadata);
            return self.write(")");
        }
        if (runtime.eq(code, "s")) {
            try self.write("String(value: ");
            try self.quote(runtime.stringField(ir, "v").?);
            return self.write(")");
        }
        if (runtime.eq(code, "i")) {
            const v = runtime.field(ir, "v");
            try self.write("Integer(value: ");
            if (v == .integer) try self.write(try runtime.integerText(self.allocator, v.integer)) else if (v == .float) try self.write(try runtime.numberText(self.allocator, v.float)) else return error.InvalidIR;
            return self.write(")");
        }
        if (runtime.eq(code, "x")) {
            try self.write("Binary(value: ");
            try self.binary(try runtime.decodeBytes(self.allocator, runtime.field(ir, "v")));
            return self.write(")");
        }
        const codes = [_]struct { []const u8, []const u8 }{ .{ "ta", "Tail" }, .{ "c", "Cons" }, .{ "z", "Vacant" }, .{ "u", "Empty" }, .{ "n", "NoCases" } };
        for (codes) |pair| if (runtime.eq(code, pair[0])) return self.write(pair[1]);
        const labelled = [_]struct { []const u8, []const u8 }{ .{ "v", "Variable" }, .{ "e", "Extend" }, .{ "g", "Select" }, .{ "o", "Overwrite" }, .{ "t", "Tag" }, .{ "m", "Case" }, .{ "p", "Perform" }, .{ "h", "Handle" }, .{ "b", "Builtin" } };
        for (labelled) |pair| if (runtime.eq(code, pair[0])) {
            try self.write(pair[1]);
            try self.write(if (runtime.eq(code, "b")) "(identifier: " else "(label: ");
            try self.quote(runtime.stringField(ir, "l").?);
            return self.write(")");
        };
        if (runtime.eq(code, "#") or runtime.eq(code, "@") or runtime.eq(code, ".")) return self.reference(ir, code);
        return error.InvalidIR;
    }
};
