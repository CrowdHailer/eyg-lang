// https://stackoverflow.com/questions/6122571/simple-non-secure-hash-function-for-javascript
export function hashCode(str) {
    let hash = 0;
    for (let i = 0, len = str.length; i < len; i++) {
        let chr = str.charCodeAt(i);
        hash = (hash << 5) - hash + chr;
        // hash |= 0; // Convert to 32bit integer
        hash = hash >>> 0
    }
    return hash.toString(16);
  }


// https://www.stefanjudis.com/snippets/how-trigger-file-downloads-with-javascript/
export function downloadFile(file) {
    // Create a link and set the URL using `createObjectURL`
    const link = document.createElement("a");
    link.style.display = "none";
    link.href = URL.createObjectURL(file);
    link.download = file.name;
  
    // It needs to be added to the DOM so it can be clicked
    document.body.appendChild(link);
    link.click();
  
    // To make this work on Firefox we need to wait
    // a little while before removing it.
    setTimeout(() => {
      URL.revokeObjectURL(link.href);
      link.parentNode.removeChild(link);
    }, 0);
  }
  
  