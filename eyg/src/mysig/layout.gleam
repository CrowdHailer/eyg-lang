import mysig/asset

pub const css = asset.Asset("layout", <<css_:utf8>>, asset.Css)

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

.separator {
  display: flex;
  align-items: center;
  text-align: center;
}

.separator::before,
.separator::after {
  content: '';
  flex: 1;
  border-bottom-width: 1px;
  border-color: inherit;
}

.separator:not(:empty)::before {
  margin-right: .25em;
}

.separator:not(:empty)::after {
  margin-left: .25em;
}
"
