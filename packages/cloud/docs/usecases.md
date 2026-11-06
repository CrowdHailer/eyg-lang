# Use cases

What a person can do with the cloud shell.
Each group is shown in its own video, recorded by [record.js](./record.js).

## Write and run EYG ([editing.webm](./editing.webm))

1. **Open a fresh shell.** Visiting `/` starts a new session with the terminal focused.
2. **See the keys.** `?` shows every editing key; `?` again hides it.
3. **Build code with keys.** Each key is an edit on the selected node, the same as the CLI's TUI: `n` an integer, `s` a string, `e` assigns to a variable, `j` a builtin, `c` calls, `v` a variable, and so on.
4. **Move around the code.** Arrow keys move the selection, `a` widens it, space jumps to the next blank.
5. **See types while editing.** The status line shows the type of the selection, what a blank needs, or a type error. Variables from earlier commands are typed.
6. **Paste source.** Pasted EYG text replaces the selection.
7. **Undo and redo.** `z` and `Z`.
8. **Run.** Enter runs the program and shows its value.
9. **Keep variables.** Assignments stay in scope for later commands.
10. **See errors clearly.** Runtime errors are red with a dimmed hint, and change nothing.
11. **Print coloured output.** ANSI colour codes written with `StandardOut` are shown in colour.
12. **Recall earlier commands.** On an empty prompt, Up and Down bring back earlier commands to edit.
13. **Stop a long command.** A running command says so; Esc stops it. Commands also stop after 30 seconds.

## Files and imports ([files.webm](./files.webm))

14. **Write and read files.** File effects act on the session's in-memory file system. Writes create missing directories.
15. **Watch the root change.** The header shows the CID of the file system root. It changes with every write and is the same for the same contents. Files and directories are standard UnixFS blocks.
16. **Import a file.** `q` picks a file from the file system to import in place of the selection. Imports are type checked while editing.
17. **Import relative to a module.** A module's own imports are relative to its directory.

## Mount files ([mount.webm](./mount.webm))

18. **Mount a folder.** `mount folder` uploads a folder from the computer.
19. **Drop files.** Files or folders dropped on the terminal are uploaded the same way.
20. **Choose where they go.** The terminal asks for a directory, suggesting the existing ones; new directories are created.
21. **Never overwrite.** Mounting over an existing name is refused, and the dialog stays open to choose again. Esc cancels.
22. **Use mounted code.** Mounted modules can be imported with `q`.

## History and forks ([history.webm](./history.webm))

23. **See every session.** The sidebar lists sessions that have run something, newest first, with their first command and how many commands they ran.
24. **Start another session.** `+ New session` opens a fresh shell; the old one stays in the list.
25. **Reopen a past session.** Its full history is shown and its prompt is ready to continue.
26. **Follow a session in two tabs.** Commands run in one tab appear in the other.
27. **Fork at any command.** Each command, and each mount, has a fork button. A fork starts a new session with the variables and files exactly as they were after that point.
28. **Know where a fork came from.** A divider marks the inherited history and links back; the header and sidebar say so too.
29. **Keep the original.** Work in a fork never changes the session it came from.
30. **Fork a fork, or from the start.** Forks can be forked again, and the banner forks an empty session.

## Small screens ([phone.webm](./phone.webm))

31. **Use it on a phone.** The session list opens from a menu button; fork buttons are always visible on touch screens.
