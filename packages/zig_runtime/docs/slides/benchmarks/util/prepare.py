#!/usr/bin/env python3
"""Generate exact-output utility ablations from canonical package sources."""
from pathlib import Path
import hashlib, json, shutil

def replace(s, old, new, count=1):
    if s.count(old) != count:
        raise ValueError(f'Expected {count} copies of {old[:80]!r}, got {s.count(old)}')
    return s.replace(old,new)

def prepare(root: Path, out: Path):
    target=out/'src';target.mkdir(parents=True,exist_ok=True)
    sources={}
    for q in (root/'src').iterdir():
        if q.is_file():
            shutil.copy2(q,target/q.name)
            sources[q.name]=hashlib.sha256(q.read_bytes()).hexdigest()
    u=target/'unicode.zig';s=u.read_text()
    s=replace(s,'const data = @import("unicode_data.zig");','const data = @import("unicode_data.zig");\npub var linear_properties = false;\npub var linear_mapping = false;\npub var allocating_utf16 = false;')
    s=replace(s,'fn properties(cp: u21) u16 {','fn properties(cp: u21) u16 {\n    if (linear_properties) { for (data.ranges) |r| { if (cp < r.first) return 0; if (cp <= r.last) return r.flags; } return 0; }')
    s=replace(s,'pub fn utf16Order(left: []const u8, right: []const u8) std.math.Order {','pub fn utf16Order(left: []const u8, right: []const u8) std.math.Order {\n    if (allocating_utf16) {\n        const a = std.unicode.utf8ToUtf16LeAlloc(std.heap.c_allocator, left) catch unreachable;\n        defer std.heap.c_allocator.free(a);\n        const b = std.unicode.utf8ToUtf16LeAlloc(std.heap.c_allocator, right) catch unreachable;\n        defer std.heap.c_allocator.free(b);\n        return std.mem.order(u16, a, b);\n    }')
    s=replace(s,'const table = if (upper) &data.upper else &data.lower;','const table = if (upper) &data.upper else &data.lower;\n    if (linear_mapping) { for (table) |r| { if (cp < r.cp) return null; if (cp == r.cp) return r.text; } return null; }')
    u.write_text(s)
    q=target/'pretty.zig';s=q.read_text()
    s=replace(s,'const A = std.mem.Allocator;','const A = std.mem.Allocator;\npub var recursive_lengths = false;\nfn docLength(doc: *const Doc) usize {\n    if (!recursive_lengths) return doc.length;\n    return switch (doc.content) {\n        .text => |t| length(t), .line => |l| length(l.flat), .nest, .group => |d| docLength(d),\n        .sequence => |items| blk: { var n: usize=0; for (items) |d| n +|= docLength(d); break :blk n; },\n    };\n}')
    s=replace(s,'column.* +|= doc.length;','column.* +|= docLength(doc);',2)
    s=replace(s,'column.* +| inner.length <= width','column.* +| docLength(inner) <= width')
    q.write_text(s)
    q=target/'capture.zig';s=q.read_text()
    s=replace(s,'const std = @import("std");','const std = @import("std");\npub var repeat_free_variables = false;')
    s=replace(s,'for (names.items) |existing| if (runtime.eq(existing, name)) return;','if (!repeat_free_variables) { for (names.items) |existing| if (runtime.eq(existing, name)) return; }')
    q.write_text(s)
    shutil.copy2(Path(__file__).with_name('driver.zig'),target/'util_bench.zig')
    (out/'canonical-inputs.json').write_text(json.dumps(sources,indent=2)+'\n')
