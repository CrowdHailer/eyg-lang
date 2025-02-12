import * as dagJSON from "@ipld/dag-json";
import { CID } from 'multiformats/cid';

export function encode(object) {
    // console.log(code,name,0x0129)
    // console.log(CID.)
    const bytes = dagJSON.encode(object)
    console.log(bytes,"---",new TextDecoder().decode(bytes));
    console.log("==",dagJSON.decode(new TextEncoder().encode("{\"/\":\"QmaozNR7DZHQK1ZcU9p7QdrshMvXqWK6gpu5rmrkPdT3L4\"}")).toString())


    // Use CID to string
    // fixtures JSON
    let object2 =Uint8Array.from([1])
    const bytes2 = dagJSON.encode(object2)
    console.log(bytes2,"---",new TextDecoder().decode(bytes2));
}