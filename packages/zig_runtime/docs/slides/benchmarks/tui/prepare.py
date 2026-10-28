from pathlib import Path
import shutil,json,hashlib,difflib,argparse
cli=argparse.ArgumentParser();cli.add_argument('--package',type=Path);cli.add_argument('--output',type=Path);args=cli.parse_args()
root=args.package.resolve() if args.package else next(p for p in Path(__file__).resolve().parents if (p/'build.zig').exists() and (p/'src/main.zig').exists())
out=args.output.resolve() if args.output else Path(__file__).resolve().parent
out.mkdir(parents=True,exist_ok=True)
shutil.copytree(root/'src',out/'src',dirs_exist_ok=True)
flags=['no_cell_reserve','no_cell_intern','retained_frames','dead_annotation_walks','no_analysis_cache','no_history_cache','no_scope_cache','full_analysis_projection','no_type_text_cache','no_scope_text_cache','repeat_casefold','no_ansi_style_runs']
p=out/'src/tui.zig';s=p.read_text();s=s.replace('const std =', '\n'.join('pub var bench_'+x+': bool = false;' for x in flags)+'\nconst std =', 1)
# cell interning
s=s.replace('try cells.ensureTotalCapacity(self.cells.len);','if (!bench_no_cell_reserve) try cells.ensureTotalCapacity(self.cells.len);',1)
s=s.replace('if (interned.get(cell)) |encoded| {','if (!bench_no_cell_intern) if (interned.get(cell)) |encoded| {')
s=s.replace('                continue;\n            }\n            const encoded = try object(a, &.{','                continue;\n            };\n            const encoded = try object(a, &.{',1)
s=s.replace('            try interned.put(cell, encoded);','            if (!bench_no_cell_intern) try interned.put(cell, encoded);',1)
# retained layout and frames, using same timer/reset driver
needle='    pub fn frameAlloc(self: *Tui, output_allocator: Allocator, width: usize, height: usize) Error!J {\n'
s=s.replace(needle,needle+'        if (bench_retained_frames) {\n            const b = try self.buffer(width, height);\n            defer b.deinit();\n            return b.json(self.allocator);\n        }\n',1)
# dead annotations, same additional fields present in both conditions to isolate walks
s=s.replace('    reference_ir: J = .null,','    ty: []const u8 = "0",\n    problem: ?[]const u8 = null,\n    loading: bool = false,\n    reference_ir: J = .null,',1)
s=s.replace('        self.analysis_loading = analysis.loading_count;','        self.analysis_loading = analysis.loading_count;\n        if (bench_dead_annotation_walks) applyInfo(self.root, analysis);',1)
s=s.replace('    fn parseSource(self: *Tui, text: []const u8) !J {','    fn applyInfo(n: *Node, analysis: *const inference.Analysis) void {\n        if (analysis.info.get(@intFromPtr(n))) |info| { n.ty = info.type_text; n.problem = info.problem; n.loading = info.loading; } else { n.ty = ""; n.problem = null; n.loading = false; }\n        for (n.children.items) |c| applyInfo(c, analysis);\n    }\n    fn clearAnnotations(n: *Node) void { n.problem = null; n.ty = "0"; for (n.children.items) |c| clearAnnotations(c); }\n    fn parseSource(self: *Tui, text: []const u8) !J {',1)
s=s.replace('            const h = &self.history.items[reverse];','            const h = &self.history.items[reverse];\n            if (bench_dead_annotation_walks) clearAnnotations(h.root);',1)
s=s.replace('        const b = try self.buffer(width, height);\n        return b.ansi(output_allocator);','        defer if (bench_dead_annotation_walks) clearAnnotations(self.root);\n        const b = try self.buffer(width, height);\n        return b.ansi(output_allocator);',1)
# analysis cache and projection
s=s.replace('if (self.cached_analysis == null or key != self.analysis_hash) {','if (bench_no_analysis_cache or self.cached_analysis == null or key != self.analysis_hash) {',1)
s=s.replace('.scope_cache = &self.scope_cache,','.scope_cache = if (bench_no_scope_cache) null else &self.scope_cache,')
s=s.replace('.collect_scope = false, .collect_effects = false,','.collect_scope = bench_full_analysis_projection, .collect_effects = bench_full_analysis_projection,',1)
# annotated IR for direct inference probes
s=s.replace('    fn toIR(self: *Tui, n: *Node) Error!J {','    pub fn toIR(self: *Tui, n: *Node) Error!J {',1)
# pretty history cache
s=s.replace('    if (cache.width != width) {','    if (bench_no_history_cache or cache.width != width) {',1)
# duplicate casefold
s=s.replace('try unicode.changeCase(self.temp(), c.name, false), query))','try unicode.changeCase(self.temp(), c.name, false), if (bench_repeat_casefold) try unicode.changeCase(self.temp(), self.input_value, false) else query))',1)
# ansi style runs
s=s.replace('if (current == null or !std.meta.eql(current.?, cell.style)) {','if (bench_no_ansi_style_runs or current == null or !std.meta.eql(current.?, cell.style)) {',1)
p.write_text(s)
# inference memoization flags
p=out/'src/inference.zig';s=p.read_text();s=s.replace('const std =', 'pub var bench_no_type_text_cache: bool = false;\npub var bench_no_scope_text_cache: bool = false;\nconst std =', 1)
s=s.replace('if (c.rendered_types.get(resolved)) |text| return text;','if (!bench_no_type_text_cache) if (c.rendered_types.get(resolved)) |text| return text;')
s=s.replace('if (c.rendered_scopes.get(key)) |items| return items;','if (!bench_no_scope_text_cache) if (c.rendered_scopes.get(key)) |items| return items;')
p.write_text(s)
# main runtime configuration and custom identical-boundary ANSI/memory operations
p=out/'src/main.zig';s=p.read_text();s=s.replace('const J = std.json.Value;','var bench_unbuffered_json = false;\nconst J = std.json.Value;',1)
s=s.replace('fn printJson(value: J) !void {','fn printJson(value: J) !void {\n    if (bench_unbuffered_json) { try json_wire.write(value, std.io.getStdOut().writer()); try std.io.getStdOut().writeAll("\\n"); return; }',1)
needle='pub fn request(a: A, req: J) !J {\n';config='    const ablation = str(field(req, "ablation"));\n'
for f in flags:
 if f in ['no_type_text_cache','no_scope_text_cache']:config+='    @import("inference.zig").bench_'+f+' = equal(ablation, "'+f+'");\n'
 else:config+='    tui.bench_'+f+' = equal(ablation, "'+f+'");\n'
config+='    bench_unbuffered_json = equal(ablation, "unbuffered_json");\n'
s=s.replace(needle,needle+config,1)
needle='    if (equal(op, "bench_tui")) {'
custom='''    if (equal(op, "bench_ansi") or equal(op, "bench_static") or equal(op, "bench_analysis") or equal(op, "frame_memory")) {
        const width = number(field(req, "width"), 80);
        const height = number(field(req, "height"), 24);
        const events = field(req, "events");
        var samples = std.ArrayList(J).init(a);
        var sizes = std.ArrayList(J).init(a);
        var output = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer output.deinit();
        const iterations = number(field(req, "iterations"), 100);
        for (0..iterations) |_| {
            var iteration = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer iteration.deinit();
            var shell = tui.Tui.init(iteration.allocator());
            defer shell.shutdown();
            shell.sandboxed = true;
            if (events == .array) for (events.array.items) |event| { try shell.event(event); };
            if (equal(op, "frame_memory")) {
                _ = try shell.frameAlloc(output.allocator(), width, height);
                _ = output.reset(.retain_capacity);
                const before = iteration.queryCapacity();
                for (0..16) |_| { _ = try shell.frameAlloc(output.allocator(), width, height); _ = output.reset(.retain_capacity); }
                try sizes.append(.{ .integer = @intCast(iteration.queryCapacity() - before) });
            } else if (equal(op, "bench_analysis")) {
                const inf = @import("inference.zig");
                try shell.event(try parser.object(a, &.{ .{ "paste", field(req, "source") } }));
                const program = try shell.toIR(shell.root);
                for (0..20) |_| {
                    var analysis_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer analysis_arena.deinit();
                    var timer = try std.time.Timer.start();
                    const analysis = try inf.analyzeWithOptions(analysis_arena.allocator(), program, shell.engine.scope, .{ .scope_cache = if (tui.bench_no_scope_cache) null else &shell.scope_cache, .collect_paths = true });
                    try samples.append(.{ .integer = @intCast(timer.read()) });
                    try sizes.append(.{ .integer = @intCast(analysis.info.count()) });
                }
            } else if (equal(op, "bench_static")) {
                _ = try shell.frameAlloc(output.allocator(), width, height);
                _ = output.reset(.retain_capacity);
                for (0..20) |_| {
                    var timer = try std.time.Timer.start();
                    const cpu_start = try threadCpuNanoseconds();
                    const force = field(req, "force_analysis");
                    if (force == .bool and force.bool) shell.cached_analysis = null;
                    _ = try shell.frameAlloc(output.allocator(), width, height);
                    _ = output.reset(.retain_capacity);
                    _ = (try threadCpuNanoseconds()) - cpu_start;
                    try samples.append(.{ .integer = @intCast(timer.read()) });
                }
            } else {
                _ = try shell.renderAnsiAlloc(output.allocator(), width, height);
                _ = output.reset(.retain_capacity);
                for (0..20) |_| {
                    var timer = try std.time.Timer.start();
                    const cpu_start = try threadCpuNanoseconds();
                    const bytes = try shell.renderAnsiAlloc(output.allocator(), width, height);
                    const size = bytes.len;
                    _ = output.reset(.retain_capacity);
                    _ = (try threadCpuNanoseconds()) - cpu_start;
                    try samples.append(.{ .integer = @intCast(timer.read()) });
                    try sizes.append(.{ .integer = @intCast(size) });
                }
            }
        }
        return parser.object(a, &.{ .{ "samples_ns", .{ .array = samples } }, .{ "sizes", .{ .array = sizes } } });
    }
'''
s=s.replace(needle,custom+needle,1);p.write_text(s)
# record exact source provenance and all deviations
meta={'baseline_sha256':{},'variant_sha256':{},'flags':flags,'notes':['Runtime flags disable one optimization at a time in the same executable. Added legacy annotation fields remain present for both walk states, isolating traversal rather than Node-size reduction.','All normal bench_tui requests retain the final timer boundary including frame output reset and paired clock reads.']}
for name in ['main.zig','tui.zig','inference.zig']:
 before=(root/'src'/name).read_text();after=(out/'src'/name).read_text()
 meta['baseline_sha256'][name]=hashlib.sha256(before.encode()).hexdigest();meta['variant_sha256'][name]=hashlib.sha256(after.encode()).hexdigest()
 (out/(name+'.diff')).write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='canonical/'+name,tofile='ablation/'+name)))
(out/'source-provenance.json').write_text(json.dumps(meta,indent=2)+'\n')
