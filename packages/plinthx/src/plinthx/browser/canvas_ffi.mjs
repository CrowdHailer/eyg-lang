import { Result$Ok, Result$Error } from '../../gleam.mjs';
export async function image(url) {
  try { const image=new Image(); image.src=url; await image.decode(); return Result$Ok(image); }
  catch (error) { return Result$Error(String(error)); }
}
export const context = node => node.getContext('2d');
export const fillStyle = (context,color) => { context.fillStyle=color; };
export const fillRect = (context,x,y,width,height) => { context.fillRect(x,y,width,height); };
export const drawImage = (context,image,sx,sy,sw,sh,dx,dy,dw,dh) => { context.drawImage(image,sx,sy,sw,sh,dx,dy,dw,dh); };
export function toDataUrl(node) {
  try { return Result$Ok(node.toDataURL()); }
  catch (error) { return Result$Error(String(error)); }
}
export const encodePng = node => new Promise(resolve => {
  try {
    node.toBlob(blob => {
      if (!blob) { resolve(Result$Error('Canvas encoding failed')); return; }
      const reader=new FileReader();
      reader.onload=()=>resolve(Result$Ok(reader.result));
      reader.onerror=()=>resolve(Result$Error(String(reader.error)));
      reader.readAsDataURL(blob);
    },'image/png');
  } catch (error) { resolve(Result$Error(String(error))); }
});
