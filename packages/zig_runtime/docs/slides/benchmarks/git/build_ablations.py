from pathlib import Path
import hashlib,json,subprocess,time,os
root=(Path(os.environ['EYG_SLIDES_PACKAGE']) if 'EYG_SLIDES_PACKAGE' in os.environ else next(parent for parent in Path(__file__).resolve().parents if (parent/'src/git.zig').is_file() and (parent/'build.zig').is_file()));out=root/'work/slides/git';out.mkdir(parents=True,exist_ok=True)
source=(root/'src/git.zig').read_text();write=(root/'src/git_write.zig').read_text();config=(root/'src/git_config.zig').read_text()
variants={'current':source}
variants['no_object_cache']=source.replace('''        // Budget decoded immutable data; refs and config are always read anew.
        if (self.cache.count() >= 512 or self.cache_bytes + value.bytes.len > 16 * 1024 * 1024) return;
        try self.cache.put(try self.allocator.dupe(u8, key), value);
        self.cache_bytes += value.bytes.len;''','''        _ = self; _ = key; _ = value;''')
variants['reload_indexes']=source.replace('''        if (self.indexed) return;
        self.indexed = true;''','''        self.indexes.clearRetainingCapacity();
        self.indexed = true;''')
start='''            const bucket = hash[0];
            var low: usize = if (bucket == 0) 0 else be32(idx.bytes[8 + (@as(usize, bucket) - 1) * 4 ..][0..4]);
            var high: usize = be32(idx.bytes[8 + @as(usize, bucket) * 4 ..][0..4]);'''
variants['no_fanout']=source.replace(start,'''            var low: usize = 0;
            var high: usize = idx.count;''')
variants['linear_index']=variants['no_fanout'].replace('''            var high: usize = idx.count;''','''            const high: usize = idx.count;''').replace('''                const mid = low + (high - low) / 2;''','''                const mid = low;''').replace('''                    .gt => high = mid,''','''                    .gt => low = mid + 1,''')
cheap='''            if (c.timestamp < since or c.timestamp > until or std.mem.indexOf(u8, c.message, contains) == null or std.mem.indexOf(u8, c.author, author) == null) continue;
'''
variants['path_before_metadata']=source.replace(cheap,'').replace('''            try result.append(try commitJson(a, c));''',cheap+'''            try result.append(try commitJson(a, c));''')
variants['scan_after_limit']=source.replace('''            if (result.items.len >= limit or scanned >= scan_limit) break;''','''            if (scanned >= scan_limit) break;''').replace('''            try result.append(try commitJson(a, c));''','''            if (result.items.len < limit) try result.append(try commitJson(a, c));''')
variants['no_delta_preallocation']=source.replace('''    var result = try std.ArrayList(u8).initCapacity(a, target_size);''','''    var result = std.ArrayList(u8).init(a);''')
start_hash=source.index('fn verifyObject(');end_hash=source.index('\nfn parseOid(',start_hash)
new_hash='''fn verifyObject(a: Allocator, id: []const u8, value: Object) !void {
    var raw = std.ArrayList(u8).init(a);
    try raw.writer().print("{s} {d}\\x00", .{ value.kind, value.bytes.len });
    try raw.appendSlice(value.bytes);
    const digest = sha1(raw.items);
    const wanted = try parseOid(id);
    if (!std.mem.eql(u8, &digest, &wanted)) return error.ObjectChecksum;
}'''
variants['concatenate_before_hash']=(source[:start_hash]+new_hash+source[end_hash:]).replace('''try verifyObject(id, value);''','''try verifyObject(self.allocator, id, value);''')
variants['default_write_compression']=source
variants['whole_pack_read']=source.replace('''        try file.seekTo(offset);
        var buffered = std.io.bufferedReader(file.reader());''','''        try file.seekTo(0);
        const whole_pack = try file.readToEndAlloc(self.allocator, @intCast(stat.size));
        var buffered = std.io.fixedBufferStream(whole_pack[@intCast(offset)..]);''')
manifest={}
for name,s in variants.items():
 assert name in ['current','default_write_compression'] or s!=source,name
 p=out/name;p.mkdir(exist_ok=True)
 (p/'git.zig').write_text(s);(p/'git_write.zig').write_text(write.replace('.level = .fast','.level = .default') if name=='default_write_compression' else write);(p/'git_config.zig').write_text(config)
 (p/'driver.zig').write_text((root/'git/driver.zig').read_text())
 manifest[name]={'git_sha256':hashlib.sha256(s.encode()).hexdigest(),'git_write_sha256':hashlib.sha256((p/'git_write.zig').read_bytes()).hexdigest()}
(out/'variants.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Compile variants before the exclusive timing window.
for name in variants:
 p=out/name;cmd=[str(root/'scripts/zig'),'build-exe','-OReleaseFast','--dep','git','-Mroot='+str(p/'driver.zig'),'-Mgit='+str(p/'git.zig'),'-femit-bin='+str(p/'driver')]
 start=time.monotonic();r=subprocess.run(cmd,cwd=root,text=True,capture_output=True)
 (p/'build.log').write_text(r.stdout+r.stderr)
 print(name,r.returncode,round(time.monotonic()-start,2),flush=True)
 if r.returncode:raise SystemExit(r.returncode)
 manifest[name]['binary_sha256']=hashlib.sha256((p/'driver').read_bytes()).hexdigest()
 (out/'variants.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Build the two allocation/hash/compression microbenchmarks from the same source variants.
kernel = Path(__file__).with_name('git_kernel.zig')
if not kernel.exists(): kernel = Path(__file__).with_name('kernel.zig')
(out/'kernel.zig').write_text(kernel.read_text())
for variant, name in [('current','kernel-current'),('no_delta_preallocation','kernel-no-prealloc')]:
 cmd=[str(root/'scripts/zig'),'build-exe','-OReleaseFast','--dep','git','-Mroot='+str(out/'kernel.zig'),'-Mgit='+str(out/variant/'git.zig'),'-femit-bin='+str(out/name)]
 r=subprocess.run(cmd,cwd=root,text=True,capture_output=True)
 (out/(name+'-build.log')).write_text(r.stdout+r.stderr)
 print(name,r.returncode,flush=True)
 if r.returncode:raise SystemExit(r.returncode)

(out/'extra-variant.json').unlink(missing_ok=True)
