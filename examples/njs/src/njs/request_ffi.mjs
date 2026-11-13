export const method = r => r.method;
export const path = r => r.uri;
export const headers = r => Object.keys(r.headersIn);
export const log = (r, message) => r.log(message);
export const subrequest = (r, path) => r.subrequest(path);
export const finish = (r, status, body) => r.return(status, body);
