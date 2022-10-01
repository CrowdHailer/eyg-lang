// import as a module allows it to have await at top level

function randomChar() {
  var index = Math.floor(Math.random() * 32);
  // Generate Number character
  if (index < 10) {
    return String(index);
    //   // Generate capital letters
    // } else if (index < 36) {
    //   return String.fromCharCode(index + 55);
  } else {
    // Generate small-case letters
    return String.fromCharCode(index + 61);
  }
}

function randomString(length) {
  var result = "";
  while (length > 0) {
    result += randomChar();
    length--;
  }
  return result;
}

function getName() {
  const key = "node";
  const saved = localStorage.getItem(key);
  if (saved) {
    return saved;
  } else {
    const generated = randomString(5);
    localStorage.setItem(key, generated);
    return localStorage.getItem(key);
  }
}

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const node = getName();
const poll = async function () {
  while (true) {
    let response = await fetch("/config");
    if (response.status == 200) {
      const config = await response.json();
      if (config[node]) {
        console.log(config[node]);
      } else {
        console.log("nothing");
        window.document.body.innerHTML = `<div class="vstack"><div>${node} no program</div></div>`;
      }
      await delay(1000);
    }
  }
};
poll();
