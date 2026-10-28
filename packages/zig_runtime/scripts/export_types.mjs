// Export fixed type declarations, not inference results, from the pinned source.
// Usage: node scripts/export_types.mjs /absolute/oracle-next-tui
import {pathToFileURL,fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {resolve,dirname} from 'node:path';
import {writeFile} from 'node:fs/promises';
const root=resolve(process.argv[2]);
const expected='be502aa03df926a8f9df474a0a7fe16c8fb14fbd';
if(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim()!==expected)throw new Error('oracle SHA mismatch');
if(execFileSync('git',['-C',root,'status','--porcelain','--untracked-files=no'],{encoding:'utf8'}).trim())throw new Error('oracle tracked files are dirty');
const build=resolve(root,'packages/gleam_cli/build/dev/javascript');
const load=p=>import(pathToFileURL(resolve(build,p)).href);
const [infer,computer,iface]=await Promise.all([
'eyg_analysis/eyg/analysis/inference/levels_j/contextual.mjs',
'loam/loam/platform/computer.mjs','touch_grass/touch_grass/interface.mjs'].map(load));
// The second field of EffectExtend is a tuple, all other type arguments are
// individual type constructors. Var keys are [quantified,id] for schemes.
function type(t){let name=t.constructor.name;if(name==='Var')return ['Var',t.key];if(name==='Fun')return [name,type(t[0]),type(t[1]),type(t[2])];if(name==='RowExtend')return [name,t[0],type(t[1]),type(t[2])];if(name==='EffectExtend')return [name,t[0],type(t[1][0]),type(t[1][1]),type(t[2])];if(t[0])return [name,type(t[0])];return [name];}
const builtins=Object.fromEntries(Array.from(infer.builtins(),([name,scheme])=>[name,type(scheme)]));
const effects=Array.from(iface.types(computer.effects()),([name,[lift,reply]])=>[name,type(lift),type(reply)]);
const out=resolve(dirname(fileURLToPath(import.meta.url)),'../src');
await writeFile(resolve(out,'builtin_types.json'),JSON.stringify(builtins,null,2)+'\n');
await writeFile(resolve(out,'computer_types.json'),JSON.stringify(effects,null,2)+'\n');
console.log(Object.keys(builtins).length,effects.length);
