import mysig/asset

pub fn css() {
  asset.load("src/mysig/layout.css")
}

// https://css-tricks.com/box-sizing/#aa-universal-box-sizing-with-inheritance
const css_ = "
html {
  box-sizing: border-box;
}
*, *:before, *:after {
  box-sizing: inherit;
}

.vstack {
  display: flex;
  flex-direction: column;
  align-items: center;
  min-height: 100%;
  justify-content: center;
}

body > .vstack, body.vstack {
  min-height: 100vh;
}

.vstack>*.expand {
  flex-grow: 1;
}

.vstack>*.cover {
  align-self: stretch;
}

.hstack {
  display: flex;
  /* not sure why this needs width 100% but vstack is flex grow */
  width: 100%;
  align-items: center;
  justify-content: center;
}

body>.hstack {
  min-height: 100vh;
}

.hstack>*.expand {
  flex-grow: 1;
}

.hstack>*.cover {
  align-self: stretch;
}
"
