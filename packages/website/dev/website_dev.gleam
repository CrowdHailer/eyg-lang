import argv
import gleam/io
import gleam/string
import simplifile

pub fn main() {
  case argv.load().arguments {
    ["pages", dir] -> {
      let assert Ok(_) = simplifile.create_directory_all(dir)
      let assert Ok(_) =
        simplifile.write(
          dir <> "/index.html",
          "<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"UTF-8\" />
    <link rel=\"icon\" type=\"image/svg+xml\" href=\"/favicon.svg\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>website</title>
  </head>
  <body>
    <div id=\"app\">Hello2</div>
    <script type=\"module\">
      import { main } from \"/src/website.gleam\";
      main()
    </script>
  </body>
</html>",
        )
      let assert Ok(_) = simplifile.create_directory_all(dir <> "/about")
      let assert Ok(_) =
        simplifile.write(
          dir <> "/about/index.html",
          "<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"UTF-8\" />
    <link rel=\"icon\" type=\"image/svg+xml\" href=\"/favicon.svg\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>website</title>
  </head>
  <body>
    <div id=\"app\">Hello2 About</div>
    <script type=\"module\">
      import { main } from \"/src/website/foo.gleam\";
      main()
    </script>
  </body>
</html>",
        )
      Nil
    }
    args -> {
      io.println("unsupported args: " <> string.join(args, " "))
      Nil
    }
  }
}
