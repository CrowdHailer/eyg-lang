import mysig

pub const css = mysig.Asset("neo", <<css_:utf8>>, mysig.Css)

const css_ = ":root {
    --neo-blue-1: #daf5f0;
    --neo-blue-2: #a7dbd8;
    --neo-blue-3: #87ceeb;
    --neo-blue-4: #69d2e7;

    --neo-green-1: #b5d2ad;
    --neo-green-2: #bafca2;
    --neo-green-3: #90ee90;
    --neo-green-4: #7fbc8c;

    --neo-yellow-1: #fdfd96;
    --neo-yellow-2: #ffdb58;
    --neo-yellow-3: #f4d738;
    --neo-yellow-4: #e3a018;

    --neo-orange-1: #f8d6b3;
    --neo-orange-2: #ffa07a;
    --neo-orange-3: #ff7a5c;
    --neo-orange-4: #ff6b6b;

    --neo-pink-1: #fcdfff;
    --neo-pink-2: #ffc0cb;
    --neo-pink-3: #ffb2ef;
    --neo-pink-4: #ff69b4;

    --neo-purple-1: #e3dff2;
    --neo-purple-2: #c4a1ff;
    --neo-purple-3: #a388ee;
    --neo-purple-4: #9723c9;
  }

  .blue-gradient {
    background: linear-gradient(
      0.25turn,
      var(--neo-blue-1),
      var(--neo-blue-3)
    );
  }

  .green-gradient {
    background: linear-gradient(
      0.25turn,
      var(--neo-green-2),
      var(--neo-green-3)
    );
  }

  .yellow-gradient {
    background: linear-gradient(
      0.25turn,
      var(--neo-yellow-1),
      var(--neo-yellow-3)
    );
  }
  .orange-gradient {
    background: linear-gradient(
      0.25turn,
      var(--neo-orange-3),
      var(--neo-orange-4)
    );
  }
  .pink-gradient {
    background: linear-gradient(
      0.25turn,
      var(--neo-pink-2),
      var(--neo-pink-3)
    );
  }
  .purple-gradient {
    background: linear-gradient(
      0.25turn,
      var(--neo-purple-1),
      var(--neo-purple-3)
    );
  }

  .text-blue-1 {
    color: var(--neo-blue-1);
  }
  .text-blue-2 {
    color: var(--neo-blue-2);
  }
  .text-blue-3 {
    color: var(--neo-blue-3);
  }
  .text-blue-4 {
    color: var(--neo-blue-4);
  }
  .text-green-1 {
    color: var(--neo-green-1);
  }
  .text-green-2 {
    color: var(--neo-green-2);
  }
  .text-green-3 {
    color: var(--neo-green-3);
  }
  .text-green-4 {
    color: var(--neo-green-4);
  }
  .text-yellow-1 {
    color: var(--neo-yellow-1);
  }
  .text-yellow-2 {
    color: var(--neo-yellow-2);
  }
  .text-yellow-3 {
    color: var(--neo-yellow-3);
  }
  .text-yellow-4 {
    color: var(--neo-yellow-4);
  }
  .text-orange-1 {
    color: var(--neo-orange-1);
  }
  .text-orange-2 {
    color: var(--neo-orange-2);
  }
  .text-orange-3 {
    color: var(--neo-orange-3);
  }
  .text-orange-4 {
    color: var(--neo-orange-4);
  }
  .text-pink-1 {
    color: var(--neo-pink-1);
  }
  .text-pink-2 {
    color: var(--neo-pink-2);
  }
  .text-pink-3 {
    color: var(--neo-pink-3);
  }
  .text-pink-4 {
    color: var(--neo-pink-4);
  }
  .text-purple-1 {
    color: var(--neo-purple-1);
  }
  .text-purple-2 {
    color: var(--neo-purple-2);
  }
  .text-purple-3 {
    color: var(--neo-purple-3);
  }
  .text-purple-4 {
    color: var(--neo-purple-4);
  }

  .bg-blue-1 {
    background-color: var(--neo-blue-1);
  }
  .bg-blue-2 {
    background-color: var(--neo-blue-2);
  }
  .bg-blue-3 {
    background-color: var(--neo-blue-3);
  }
  .bg-blue-4 {
    background-color: var(--neo-blue-4);
  }
  .bg-green-1 {
    background-color: var(--neo-green-1);
  }
  .bg-green-2 {
    background-color: var(--neo-green-2);
  }
  .bg-green-3 {
    background-color: var(--neo-green-3);
  }
  .bg-green-4 {
    background-color: var(--neo-green-4);
  }
  .bg-yellow-1 {
    background-color: var(--neo-yellow-1);
  }
  .bg-yellow-2 {
    background-color: var(--neo-yellow-2);
  }
  .bg-yellow-3 {
    background-color: var(--neo-yellow-3);
  }
  .bg-yellow-4 {
    background-color: var(--neo-yellow-4);
  }
  .bg-orange-1 {
    background-color: var(--neo-orange-1);
  }
  .bg-orange-2 {
    background-color: var(--neo-orange-2);
  }
  .bg-orange-3 {
    background-color: var(--neo-orange-3);
  }
  .bg-orange-4 {
    background-color: var(--neo-orange-4);
  }
  .bg-pink-1 {
    background-color: var(--neo-pink-1);
  }
  .bg-pink-2 {
    background-color: var(--neo-pink-2);
  }
  .bg-pink-3 {
    background-color: var(--neo-pink-3);
  }
  .bg-purple-1 {
    background-color: var(--neo-purple-1);
  }
  .bg-purple-2 {
    background-color: var(--neo-purple-2);
  }
  .bg-purple-3 {
    background-color: var(--neo-purple-3);
  }
  .bg-purple-4 {
    background-color: var(--neo-purple-4);
  }

  .border-blue-1 {
    --tw-border-opacity: 1;
    border-color: var(--neo-blue-1);
  }
  .border-blue-2 {
    --tw-border-opacity: 1;
    border-color: var(--neo-blue-2);
  }
  .border-blue-3 {
    --tw-border-opacity: 1;
    border-color: var(--neo-blue-3);
  }
  .border-blue-4 {
    --tw-border-opacity: 1;
    border-color: var(--neo-blue-4);
  }
  .border-green-1 {
    --tw-border-opacity: 1;
    border-color: var(--neo-green-1);
  }
  .border-green-2 {
    --tw-border-opacity: 1;
    border-color: var(--neo-green-2);
  }
  .border-green-3 {
    --tw-border-opacity: 1;
    border-color: var(--neo-green-3);
  }
  .border-green-4 {
    --tw-border-opacity: 1;
    border-color: var(--neo-green-4);
  }
  .border-yellow-1 {
    --tw-border-opacity: 1;
    border-color: var(--neo-yellow-1);
  }
  .border-yellow-2 {
    --tw-border-opacity: 1;
    border-color: var(--neo-yellow-2);
  }
  .border-yellow-3 {
    --tw-border-opacity: 1;
    border-color: var(--neo-yellow-3);
  }
  .border-yellow-4 {
    --tw-border-opacity: 1;
    border-color: var(--neo-yellow-4);
  }
  .border-orange-1 {
    --tw-border-opacity: 1;
    border-color: var(--neo-orange-1);
  }
  .border-orange-2 {
    --tw-border-opacity: 1;
    border-color: var(--neo-orange-2);
  }
  .border-orange-3 {
    --tw-border-opacity: 1;
    border-color: var(--neo-orange-3);
  }
  .border-orange-4 {
    --tw-border-opacity: 1;
    border-color: var(--neo-orange-4);
  }
  .border-pink-1 {
    --tw-border-opacity: 1;
    border-color: var(--neo-pink-1);
  }
  .border-pink-2 {
    --tw-border-opacity: 1;
    border-color: var(--neo-pink-2);
  }
  .border-pink-3 {
    --tw-border-opacity: 1;
    border-color: var(--neo-pink-3);
  }
  .border-pink-4 {
    --tw-border-opacity: 1;
    border-color: var(--neo-pink-4);
  }
  .border-purple-1 {
    --tw-border-opacity: 1;
    border-color: var(--neo-purple-1);
  }
  .border-purple-2 {
    --tw-border-opacity: 1;
    border-color: var(--neo-purple-2);
  }
  .border-purple-3 {
    --tw-border-opacity: 1;
    border-color: var(--neo-purple-3);
  }
  .border-purple-4 {
    --tw-border-opacity: 1;
    border-color: var(--neo-purple-4);
  }

  .neo-shadow {
    box-shadow: 6px 6px black;
  }

  .drop {
    padding-bottom: 30px !important;
  }
  .drop + * > *:first-child > *:first-child {
    margin-top: -30px !important;
  }

  body {
    font-family: \"Franklin Gothic Medium\", \"Arial Narrow\", Arial, sans-serif;
  }

  h2 {
    display: inline-block;
    /* color: white; */
    font-weight: bold;
    font-size: 1.5em;
    position: relative;
    margin: 16px 0;
    z-index: 1;
  }

  h2::after {
    position: absolute;
    bottom: 0;
    left: 0;
    padding: 0 4px;
    transform: translateX(-14px);
    border-radius: 3px;
    content: \"\";
    display: block;
    height: 50%;
    width: 100%;
    background: var(--neo-green-4);
    z-index: -1;
  }

  h3.blocked {
    display: inline-block;
    /* color: white; */
    /* font-weight: bold; */
    font-size: 1.2em;
    position: relative;
    margin: 10px 0;
    z-index: 1;
  }

  h3.blocked::after {
    position: absolute;
    bottom: 0;
    left: 0;
    padding: 0 4px;
    transform: translateX(-14px);
    border-radius: 3px;
    content: \"\";
    display: block;
    height: 50%;
    width: 100%;
    background: var(--neo-green-4);
    z-index: -1;
  }
"
