# hub

Backend application to store packages and signatories.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

http://localhost:8080/registry/modules/baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma

```
URI=""

echo "Connecting: $URI"

harlequin -a postgres postgres://postgres:abchdo1mcLqP@127.0.0.1:5432/postgres
```

Use a subshell:
bash(source .env && your-command)
The parentheses create a subshell — variables are set inside it, your command runs with them, and when it exits nothing leaks back to your parent shell.

source .env won't work they become shell variables not environment variables and therefore not available to the erlang shell.

(set -a; source ../eyg.run/.env; set +a; gleam test)

```sh
#!/bin/bash
# run_with_env.sh
set -a
source "$1"
set +a
shift
"$@"
```