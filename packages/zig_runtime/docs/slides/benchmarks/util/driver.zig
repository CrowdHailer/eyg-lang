const std = @import("std");
const u = @import("unicode.zig");
const p = @import("pretty.zig");
const c = @import("capture.zig");
const r = @import("interpreter.zig");
const parser = @import("parser.zig");
var checksum: u64 = 0;
const Case = enum { utf16, properties, mapping, lengths, capture };
fn configure(kind: Case, before: bool) void {
    u.allocating_utf16 = kind == .utf16 and before;
    u.linear_properties = kind == .properties and before;
    u.linear_mapping = kind == .mapping and before;
    p.recursive_lengths = kind == .lengths and before;
    c.repeat_free_variables = kind == .capture and before;
}
const strings = [_][]const u8{ "alpha", "alphaβ", "alp😀", "\u{10000}", "\u{e000}", "ééé", "👩🏿‍🚀", "Straße κόσμος", "Zebra", "a long common prefix βxyz", "a long common prefix βxzz" };
const grapheme_text = "abc é👩🏿‍🚀🇬🇧क्ष Straße κόσμος xyz 日本語";
const mapping_text = "Straße κόσμος ΟΣＡabcXYZéÉßıİﬄ Ελληνικά 日本語 😀";
fn output(kind: Case, before: bool, allocator: std.mem.Allocator) ![]const u8 {
    configure(kind, before);
    return switch (kind) {
        .utf16 => blk: {
            var a = std.ArrayList(u8).init(allocator);
            for (strings) |x| for (strings) |y| try a.append(@intCast(@intFromEnum(u.utf16Order(x,y)) + 1));
            break :blk a.toOwnedSlice();
        },
        .properties => blk: {
            var a = std.ArrayList(u8).init(allocator);
            var i: usize=0; while(i<grapheme_text.len){ i=u.graphemeEnd(grapheme_text,i);try a.append(@intCast(i)); }
            break :blk a.toOwnedSlice();
        },
        .mapping => u.changeCase(allocator, mapping_text, true),
        .lengths => blk: {
            const doc = try makeDoc(allocator);
            break :blk p.renderDocument(allocator,doc,80);
        },
        .capture => blk: {
            const value = try makeClosure(allocator);
            const ir = try c.capture(allocator,value);
            break :blk std.json.stringifyAlloc(allocator,ir,.{});
        },
    };
}
fn makeDoc(a: std.mem.Allocator) !*const p.Doc {
    const printer = p.Printer{.allocator=a};
    var doc = try printer.text("é😀alpha");
    var i: usize=0; while(i<7):(i+=1){ doc=try printer.wrap("[",try printer.sequence(&.{doc,try printer.line(", ",","),doc}),"]"); }
    return doc;
}
fn makeClosure(a: std.mem.Allocator) !r.Value {
    var code=std.ArrayList(u8).init(a);
    try code.appendSlice("let x = 42 let f = (unused) -> { [");
    var i: usize=0;while(i<128):(i+=1){if(i>0)try code.appendSlice(", ");try code.append('x');}
    try code.appendSlice("] } f");
    var engine=r.Engine.init(a);
    return engine.eval(try parser.parse(a,code.items));
}
fn sample(kind: Case,before: bool,n: usize) !u64 {
    configure(kind,before);
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const a=arena.allocator();
    const doc = if(kind==.lengths) try makeDoc(a) else undefined;
    const closure = if(kind==.capture) try makeClosure(a) else undefined;
    var temp = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer temp.deinit();
    var clock=try std.time.Timer.start();
    var i: usize=0;
    while(i<n):(i+=1) {
        switch(kind) {
            .utf16 => for(strings) |x| {for(strings) |y| {checksum +%= @intCast(@intFromEnum(u.utf16Order(x,y))+1);}},
            .properties => {var at:usize=0;while(at<grapheme_text.len){at=u.graphemeEnd(grapheme_text,at);checksum +%= at;}},
            .mapping => { const text=try u.changeCase(temp.allocator(),mapping_text,true);checksum +%= std.hash.Wyhash.hash(0,text); },
            .lengths => { const text=try p.renderDocument(temp.allocator(),doc,80);checksum +%= std.hash.Wyhash.hash(0,text); },
            .capture => { const ir=try c.capture(temp.allocator(),closure);checksum +%= ir.object.count(); },
        }
        if(kind==.mapping or kind==.lengths or kind==.capture) _=temp.reset(.retain_capacity);
    }
    return clock.read();
}
pub fn main() !void {
    var gpa=std.heap.GeneralPurposeAllocator(.{}){};defer _=gpa.deinit();const a=gpa.allocator();
    const args=try std.process.argsAlloc(a);defer std.process.argsFree(a,args);
    const verify=args.len>1 and std.mem.eql(u8,args[1],"verify");
    const out=std.io.getStdOut().writer();
    const kinds=[_]Case{.utf16,.properties,.mapping,.lengths,.capture};
    if(verify){for(kinds)|k|{var arena=std.heap.ArenaAllocator.init(a);defer arena.deinit();const before=try output(k,true,arena.allocator());const after=try output(k,false,arena.allocator());if(!std.mem.eql(u8,before,after))return error.OutputMismatch;try out.print("{s}: equivalent {d} bytes\n",.{@tagName(k),after.len});}return;}
    const ns=[_]usize{100,2000,500,100,20};
    try out.writeAll("{\"cases\":[");
    for(kinds,0..) |k,ix| {
        if(ix>0)try out.writeAll(",");
        try out.print("{{\"name\":\"{s}\",\"iterations_per_sample\":{d},\"before_ns\":[",.{@tagName(k),ns[ix]});
        _=try sample(k,true,ns[ix]);_=try sample(k,false,ns[ix]);
        var before:[31]u64=undefined;var after:[31]u64=undefined;
        for(0..31)|j|{if(j%2==0){before[j]=try sample(k,true,ns[ix]);after[j]=try sample(k,false,ns[ix]);}else{after[j]=try sample(k,false,ns[ix]);before[j]=try sample(k,true,ns[ix]);}}
        for(before,0..)|n,j|{if(j>0)try out.writeAll(",");try out.print("{d}",.{n});}
        try out.writeAll("],\"after_ns\":[");for(after,0..)|n,j|{if(j>0)try out.writeAll(",");try out.print("{d}",.{n});}try out.writeAll("]}");
    }
    try out.print("],\"checksum\":{d}}}\n",.{checksum});
}
