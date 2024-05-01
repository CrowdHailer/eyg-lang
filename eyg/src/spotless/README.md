# Spotless

Design guide to live in the main screen so getting a field just scrolls
But the overwride does everything?

CORS was never a problem when using a go implemented repl
The shell I want, using spotless and effects

the returned effect at any given position is effects below

Demo fast match for AST choose field access
Make pretty for monday

surface is a projection with binding to session -> buffer is a projection + mode

TODO multiline long lists/records
TODO Need to save from Drafting and it should handle all editable to tree transforms -> track things like variable name in destructure but will need one at creation
Every path needs to point to something valid, an expression can be a block
yes a record in a pattern is something to target exactly analagous to expression record
and moving into it goes to the first value if present

Is open/close necessary if we have a good answer for rendering only focused lines. probably

Maybe call enumarate.gleam for indexing through the tree

Is keybindings more or less low level than typing probably typing is more low level so different UI's on top
TODO spaces for every line on rendering and show only near lines
TODO Token in the background
TODO click column to add to variable or row or cell
TODO playbook for table views in spotless, fix extra wide table
TODO replay previous fn or just have scratch populated with last function
TODO allow paste button in tree current node only
TODO readonly mode for previous code on spotless
TODO show error tasks even if not awaiting on them
TODO returning code makes it possible to execute the code
How do we want to work in the situation where you have scripts

craft could be name for surface

TODO need fade out for lines up and down

Nothing in drafting session is that valuable
wire up next and previous
Handle the tenv going invalid AND errors in buffer


can DNSimple API be called from localhost
extend a record, i.e. add fields use r again
maybe action is a useless abstraction because getting a single state needs full knowledge
SelectAction - doesn't work but used to hard code the bindings
             - pressing enter triggers DoIt
             - Pressing "Space" starts the state

Action needs to return a SelectBuiltin the session mode and action return don't make a Good
pairing
Suggestions might not be available so action can always return a mode without suggestions

Maybe I should double nest the maybes first for suggestion, second if scrolling to it.

session might not have bindings

all 3 need some context
Keys have to be intercepted before going to drafting because edit shouldn't happen once code is running
Unless you turn off the ability to edit once it is running
Probably need to rebuild the select var/builtin and edit number/string
How do we get the scope at one time. When we start a selection
However where do we keep the state
fly integration if using heroku backend for spotless
TODO netlify deploy reuse token
TODO builder for browser string for open instructions, like a SQL query builder

- Morph/Transform All the actions taking the most focused type

Dont have a select multiple for records or dots in variable because want as much common path which means going back to the command mode
I'm not sure I'm keeping the ability to select rows in assign blocks so moving off them is a bit odd

Shift versions can be the same thing with no information

match on number/string/list `uncons`

picker tab to only common root

can't type spaces in label input box
