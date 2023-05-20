package fern

import (
	"fmt"
	"strconv"
	"unicode"

	"github.com/gdamore/tcell/v2"
)

const blue3 = 0x87ceeb
const green4 = 0x7fbc8c
const yellow2 = 0xffdb58
const orange4 = 0xff6b6b
const pink3 = 0xffb2ef
const purple4 = 0x9723c9

var keywordStyle = tcell.StyleDefault.Dim(true)
var missingStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(pink3))
var todoStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(orange4)).Bold(true)
var intStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(purple4))
var stringStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(green4))
var unionStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(blue3))
var effectStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(yellow2))

// view exhibit rendered
// scene or panel page is the list of rendered
type rendered struct {
	character rune
	path      []int
	offset    int
	style     tcell.Style
}

func (node Fn) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.param, buffer, info, s, tcell.StyleDefault)
	*buffer = append(*buffer, rendered{' ', s.path, len(node.param), keywordStyle})
	*buffer = append(*buffer, rendered{'-', s.path, -1, keywordStyle})
	*buffer = append(*buffer, rendered{'>', s.path, -1, keywordStyle})
	*buffer = append(*buffer, rendered{' ', s.path, -1, keywordStyle})
	node.body.print(buffer, info, situ{s.indent, s.nested, true, append(s.path, 0)})
}

// TODO call passing into function into number etc

// Each node can have it's own interpretation of what -1 means but this is a public iterface for other nodes like call
// Keeping print and keypress together because of offsets but maybe not needed
func (node Fn) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	if unicode.IsLetter(ch) || unicode.IsDigit(ch) {
		param := insertRune(node.param, offset, ch)
		return Fn{param, node.body}, []int{}, offset + 1
	}
	return node, []int{}, 0
}

func (node Fn) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	param, offset := backspaceAt(node.param, offset)
	return Fn{param, node.body}, []int{}, offset
}

func printIndent(buffer *[]rendered, indent int) {
	for i := 0; i < indent; i++ {
		*buffer = append(*buffer, rendered{' ', nil, -1, tcell.StyleDefault})
	}
}

func insertRune(s string, at int, new rune) string {
	return s[:at] + string(new) + s[at:]
}

func backspaceAt(s string, at int) (string, int) {
	if at < 1 {
		return s, 0
	}
	return s[:at-1] + s[at:], at - 1
}

func printTail(node Node, buffer *[]rendered, info map[string]int, path []int, indent int, nested bool, start int) {
	switch t := node.(type) {
	case Call:
		// TODO wrap up this switching to a fn on call
		if inner, ok := t.fn.(Call); ok {
			if _, ok := inner.fn.(Cons); ok {
				start := len(*buffer)
				*buffer = append(*buffer, rendered{',', path, 0, keywordStyle})
				*buffer = append(*buffer, rendered{' ', path, 1, keywordStyle})
				inner.arg.print(buffer, info, situ{indent, true, true, append(path, 0, 1)})
				printTail(t.arg, buffer, info, path, indent, nested, start)
			}
		}
		return
	case Tail:
		offset := len(*buffer) - start
		*buffer = append(*buffer, rendered{']', path, offset, keywordStyle})
		if !nested {
			*buffer = append(*buffer, rendered{'\n', path, offset + 1, keywordStyle})
		}
		return
	}
	start2 := len(*buffer)
	// Pressing comma on this makes a list in the tail position which is what we want
	// there is no choice between at element or tail position because it is not yet a lets itself.
	*buffer = append(*buffer, rendered{',', path, 0, keywordStyle})
	*buffer = append(*buffer, rendered{' ', path, 1, keywordStyle})
	*buffer = append(*buffer, rendered{'.', path, 2, keywordStyle})
	*buffer = append(*buffer, rendered{'.', path, 3, keywordStyle})
	node.print(buffer, info, situ{indent, true, true, path})
	offset := len(*buffer) - start2
	*buffer = append(*buffer, rendered{']', path, offset, keywordStyle})
	if !nested {
		*buffer = append(*buffer, rendered{'\n', path, offset + 1, keywordStyle})
	}
}

func printExtension(node Node, buffer *[]rendered, info map[string]int, path []int, indent int, nested bool, start int) {
	switch t := node.(type) {
	case Call:
		// TODO wrap up this switching to a fn on call
		if inner, ok := t.fn.(Call); ok {
			if group, ok := inner.fn.(Extend); ok {
				start := len(*buffer)
				*buffer = append(*buffer, rendered{',', path, 0, keywordStyle})
				*buffer = append(*buffer, rendered{' ', path, 1, keywordStyle})
				printLabel(group.label, buffer, info, situ{indent, false, false, append(path, 0, 0)}, tcell.StyleDefault)
				// same comma logic here
				*buffer = append(*buffer, rendered{':', path, 0, keywordStyle})
				*buffer = append(*buffer, rendered{' ', path, 1, keywordStyle})

				inner.arg.print(buffer, info, situ{indent, true, true, append(path, 0, 1)})
				printExtension(t.arg, buffer, info, path, indent, nested, start)
			}
		}
		return
	case Empty:
		offset := len(*buffer) - start
		*buffer = append(*buffer, rendered{'}', path, offset, keywordStyle})
		if !nested {
			*buffer = append(*buffer, rendered{'\n', path, offset + 1, keywordStyle})
		}
		return
	}
	// TODO do we make non record tails invlid
	// start2 := len(*buffer)
	// // Pressing comma on this makes a list in the tail position which is what we want
	// // there is no choice between at element or tail position because it is not yet a lets itself.
	// *buffer = append(*buffer, rendered{',', path, 0, keywordStyle})
	// *buffer = append(*buffer, rendered{' ', path, 1, keywordStyle})
	// *buffer = append(*buffer, rendered{'.', path, 2, keywordStyle})
	// *buffer = append(*buffer, rendered{'.', path, 3, keywordStyle})
	// node.print(buffer, info, situ{indent, true, true, path})
	// offset := len(*buffer) - start2
	// *buffer = append(*buffer, rendered{']', path, offset, keywordStyle})
	// if !nested {
	// 	*buffer = append(*buffer, rendered{'\n', path, offset + 1, keywordStyle})
	// }

}

func printBranch(node Node, buffer *[]rendered, info map[string]int, path []int, indent int, nested bool) {
	switch t := node.(type) {
	case Call:
		// parent handles indent same as in let
		printIndent(buffer, indent)
		// TODO wrap up this switching to a fn on call
		if inner, ok := t.fn.(Call); ok {
			if case_, ok := inner.fn.(Case); ok {
				printLabel(case_.label, buffer, info, situ{indent, false, false, append(path, 0, 0)}, unionStyle)
				*buffer = append(*buffer, rendered{' ', append(path, 0, 0), len(case_.label), unionStyle})
				inner.arg.print(buffer, info, situ{indent, false, true, append(path, 0, 1)})
				printBranch(t.arg, buffer, info, append(path, 1), indent, nested)
				return
			}
		}
	case NoCases:

		// original indent
		printIndent(buffer, indent-2)
		*buffer = append(*buffer, rendered{'}', path, 0, keywordStyle})
		if !nested {
			*buffer = append(*buffer, rendered{'\n', nil, -1, keywordStyle})
		}
		return
	}
	node.print(buffer, info, situ{indent, false, true, path})
	// original indent
	printIndent(buffer, indent-2)
	*buffer = append(*buffer, rendered{'}', nil, -1, keywordStyle})
	if !nested {
		*buffer = append(*buffer, rendered{'\n', nil, -1, keywordStyle})
	}
}

func (node Call) print(buffer *[]rendered, info map[string]int, s situ) {
	// TODO switches not if - maybe not if is list is a fn on call
	if t, ok := node.fn.(Select); ok {
		node.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 1)})
		*buffer = append(*buffer, rendered{'.', s.path, 0, keywordStyle})

		printLabel(t.label, buffer, info, situ{s.indent, false, false, append(s.path, 0)}, tcell.StyleDefault)
		if !s.nested {
			*buffer = append(*buffer, rendered{'\n', append(s.path, 0), len(t.label), keywordStyle})
		}
		return
	}
	if inner, ok := node.fn.(Call); ok {
		switch t := inner.fn.(type) {
		case Cons:
			start := len(*buffer)
			*buffer = append(*buffer, rendered{'[', s.path, 0, keywordStyle})
			inner.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 0, 1)})
			printTail(node.arg, buffer, info, append(s.path, 1), s.indent, s.nested, start)
			return
		case Extend:
			// first round of printing is outside print extend because it doesn't need ", "
			start := len(*buffer)
			*buffer = append(*buffer, rendered{'{', s.path, 0, keywordStyle})
			printLabel(t.label, buffer, info, situ{s.indent, false, false, append(s.path, 0, 0)}, tcell.StyleDefault)
			// comma doesn't work on expand
			*buffer = append(*buffer, rendered{':', s.path, 0, keywordStyle})
			*buffer = append(*buffer, rendered{' ', s.path, 0, keywordStyle})
			inner.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 0, 1)})
			printExtension(node.arg, buffer, info, append(s.path, 1), s.indent, s.nested, start)
			return
		case Case:
			printNotNode("match {", buffer, s)
			indent := s.indent + 2
			*buffer = append(*buffer, rendered{'\n', nil, -1, keywordStyle})
			// original indent
			printIndent(buffer, indent)
			printLabel(t.label, buffer, info, situ{indent, false, false, append(s.path, 0, 0)}, unionStyle)
			*buffer = append(*buffer, rendered{' ', append(s.path, 0, 0), len(t.label), unionStyle})

			inner.arg.print(buffer, info, situ{indent, false, true, append(s.path, 0, 1)})

			printBranch(node.arg, buffer, info, append(s.path, 1), indent, s.nested)

			return
		}
	}

	node.fn.print(buffer, info, situ{s.indent, true, true, append(s.path, 0)})
	start := len(*buffer)
	info[pathToString(s.path)] = start

	*buffer = append(*buffer, rendered{'(', s.path, 0, keywordStyle})
	node.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 1)})
	offset := len(*buffer) - start
	*buffer = append(*buffer, rendered{')', s.path, offset, keywordStyle})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, offset + 1, keywordStyle})
	}
}

func (node Call) keyPress(ch rune, offset int) (Node, []int, int) {
	// TODO keypress on inner elements
	if offset == 0 {
		inner, _, _ := node.fn.keyPress(ch, node.fn.contentLength())
		return Call{inner, node.arg}, []int{}, 0
	}
	inner, _, _ := node.arg.keyPress(ch, node.arg.contentLength())
	return Call{node.fn, inner}, []int{}, offset + 1
	// return node, []int{}, offset
}

func (node Call) deleteCharachter(offset int) (Node, []int, int) {
	// TODO keypress on inner elements
	return node, []int{}, offset
}

func (node Var) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s, tcell.StyleDefault)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Var) keyPress(ch rune, offset int) (Node, []int, int) {

	if offset == -1 {
		return node, []int{}, 0
	}
	if unicode.IsLetter(ch) || unicode.IsDigit(ch) {
		label := insertRune(node.label, offset, ch)
		return Var{label}, []int{}, offset + 1
	}
	if ch == '(' && offset == node.contentLength() {
		return Call{node, Vacant{}}, []int{1}, 0
	}
	if ch == '.' && offset == node.contentLength() {
		return Call{Select{}, node}, []int{0}, 0
	}
	if ch == '=' && offset == node.contentLength() {
		// Sort of the same as control e
		return Let{node.label, Vacant{}, Vacant{}}, []int{0}, 0
	}

	return node, []int{}, offset
}

func (node Var) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	if label == "" {
		return Vacant{}, []int{}, offset
	}
	return Var{label}, []int{}, offset
}

// TODO take only path in args
func printLabel(label string, buffer *[]rendered, info map[string]int, s situ, style tcell.Style) {
	info[pathToString(s.path)] = len(*buffer)
	if label == "" {
		label = "_"
		style = missingStyle
	}
	for i, ch := range label {
		*buffer = append(*buffer, rendered{ch, s.path, i, style})
	}
}

// ALso only needs the path
func printNotNode(content string, buffer *[]rendered, s situ) {
	for _, ch := range content {
		*buffer = append(*buffer, rendered{ch, s.path, -1, keywordStyle})
	}
}

func (node Let) print(buffer *[]rendered, info map[string]int, s situ) {
	indent := s.indent
	if s.block {
		indent += 2
		*buffer = append(*buffer, rendered{'{', nil, -1, keywordStyle})
		*buffer = append(*buffer, rendered{'\n', nil, -1, keywordStyle})
		// original indent
		printIndent(buffer, indent)

		defer func() {
			// needs original depth indent
			printIndent(buffer, s.indent)
			*buffer = append(*buffer, rendered{'}', nil, -1, keywordStyle})
			if !s.nested {
				*buffer = append(*buffer, rendered{'\n', nil, -1, keywordStyle})
			}
		}()
	}
	printNotNode("let ", buffer, s)
	printLabel(node.label, buffer, info, s, tcell.StyleDefault)
	*buffer = append(*buffer, rendered{' ', s.path, len(node.label), keywordStyle})
	*buffer = append(*buffer, rendered{'=', s.path, -1, keywordStyle})
	*buffer = append(*buffer, rendered{' ', s.path, -1, keywordStyle})
	node.value.print(buffer, info, situ{indent, false, true, append(s.path, 0)})
	// nested /false prints a new line
	printIndent(buffer, indent)
	node.then.print(buffer, info, situ{indent, false, false, append(s.path, 1)})
}

func (node Let) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Let{label, node.value, node.then}, []int{}, offset + 1
}

func (node Let) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Let{label, node.value, node.then}, []int{}, offset
}

func (node Vacant) print(buffer *[]rendered, info map[string]int, s situ) {
	info[pathToString(s.path)] = len(*buffer)
	content := node.note
	if content == "" {
		content = "todo"
	}
	for i, ch := range content {
		*buffer = append(*buffer, rendered{ch, s.path, i, todoStyle})
	}
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(content), keywordStyle})
	}
}

func (node Vacant) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	// TODO use same actions in center of list
	// . starts a tail
	switch ch {
	case '"':
		return String{}, []int{}, 0
	case '[':
		return Tail{}, []int{}, 0
	case '{':
		return Empty{}, []int{}, 0
	case '=':
		return Let{"", Vacant{}, Vacant{}}, []int{}, 0
		// Could be done with perform typed in
		// auto suggestion if starting with p/perform
	case '|':
		// is this a good character to have representing perform
		// what would handle be
		// TODO path into case
		return Call{Call{Case{}, Fn{"", Vacant{}}}, Vacant{}}, []int{0, 0}, 0

	case '^':
		// is this a good character to have representing perform
		// what would handle be
		return Perform{}, []int{}, 0
	}
	if digit, ok := runeToDigit(ch); ok {
		return Integer{digit}, []int{}, 1
	}
	if unicode.IsLetter(ch) && unicode.IsLower(ch) {
		return Var{string(ch)}, []int{}, 1
	}
	if unicode.IsLetter(ch) {
		return Tag{string(ch)}, []int{}, 1
	}
	return node, []int{}, 0
}

func (node Vacant) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	note, offset := backspaceAt(node.note, offset)
	return Vacant{note}, []int{}, offset
}

func (node Integer) print(buffer *[]rendered, info map[string]int, s situ) {
	info[pathToString(s.path)] = len(*buffer)
	content := fmt.Sprintf("%d", node.value)
	for i, ch := range content {
		*buffer = append(*buffer, rendered{ch, s.path, i, intStyle})
	}
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(content), keywordStyle})
	}
}

func (node Integer) keyPress(ch rune, offset int) (Node, []int, int) {
	// offset needs to be real negative number so tha position can be kept
	if offset == -1 {
		return node, []int{}, 0
	}
	if _, ok := runeToDigit(ch); ok {
		i64, err := strconv.ParseInt(insertRune(fmt.Sprintf("%d", node.value), offset, ch), 10, 64)
		if err != nil {
			// TODO log error
			return node, []int{}, 0
		}
		return Integer{int(i64)}, []int{}, offset + 1
	}
	if ch == '-' && offset == 0 && node.value > 0 {
		return Integer{-node.value}, []int{}, 1
	}
	return node, []int{}, offset
}

func (node Integer) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	value, offset := backspaceAt(fmt.Sprintf("%d", node.value), offset)
	if value == "" {
		return Vacant{}, []int{}, 0
	}
	i64, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		// TODO log error
		return node, []int{}, 0
	}
	return Integer{int(i64)}, []int{}, offset
}

func runeToDigit(ch rune) (int, bool) {
	if digit := ch - '0'; digit >= 0 && digit < 10 {
		return int(digit), true
	}
	return 0, false
}

// Does this need to be *buffer
func (node String) print(buffer *[]rendered, info map[string]int, s situ) {
	*buffer = append(*buffer, rendered{'"', s.path, -1, stringStyle})
	// start of active, maybe origin is a better name
	info[pathToString(s.path)] = len(*buffer)
	for i, ch := range node.value {
		*buffer = append(*buffer, rendered{ch, s.path, i, stringStyle})
	}
	*buffer = append(*buffer, rendered{'"', s.path, len(node.value), stringStyle})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1, keywordStyle})
	}
}

func (node String) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	value := insertRune(node.value, offset, ch)
	return String{value}, []int{}, offset + 1
}

func (node String) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	if offset == 0 && node.value == "" {
		return Vacant{}, []int{}, offset
	}
	value, offset := backspaceAt(node.value, offset)
	return String{value}, []int{}, offset
}

func (node Tail) print(buffer *[]rendered, info map[string]int, s situ) {
	*buffer = append(*buffer, rendered{'[', s.path, -1, keywordStyle})
	info[pathToString(s.path)] = len(*buffer)
	*buffer = append(*buffer, rendered{']', s.path, 0, keywordStyle})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1, keywordStyle})
	}
}

func (node Tail) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	switch ch {
	case ',':
		return Call{Call{Cons{}, Vacant{}}, Tail{}}, []int{0, 1}, 0
	}
	return node, []int{}, 0
}

func (node Tail) deleteCharachter(offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Cons) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("cons", buffer, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1, keywordStyle})
	}
}

func (node Cons) keyPress(ch rune, offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Cons) deleteCharachter(offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Empty) print(buffer *[]rendered, info map[string]int, s situ) {
	*buffer = append(*buffer, rendered{'{', s.path, -1, keywordStyle})
	info[pathToString(s.path)] = len(*buffer)
	*buffer = append(*buffer, rendered{'}', s.path, 0, keywordStyle})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1, keywordStyle})
	}
}

func (node Empty) keyPress(ch rune, offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Empty) deleteCharachter(offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Extend) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("+", buffer, s)
	printLabel(node.label, buffer, info, s, unionStyle)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Extend) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Extend{label}, []int{}, offset + 1
}

func (node Extend) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Extend{label}, []int{}, offset
}

func (node Select) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode(".", buffer, s)
	printLabel(node.label, buffer, info, s, tcell.StyleDefault)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Select) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Select{label}, []int{}, offset + 1
}

func (node Select) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Select{label}, []int{}, offset
}

func (node Overwrite) print(buffer *[]rendered, info map[string]int, s situ) {
	// is : better
	printNotNode("=", buffer, s)
	printLabel(node.label, buffer, info, s, unionStyle)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Overwrite) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Overwrite{label}, []int{}, offset + 1
}

func (node Overwrite) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Overwrite{label}, []int{}, offset
}

func (node Tag) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s, unionStyle)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), tcell.StyleDefault})
	}
}

func (node Tag) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Tag{label}, []int{}, offset + 1
}

func (node Tag) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Tag{label}, []int{}, offset
}

func (node Case) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("case ", buffer, s)
}

func (node Case) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Case{label}, []int{}, offset + 1
}

func (node Case) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Case{label}, []int{}, offset
}

func (node NoCases) print(buffer *[]rendered, info map[string]int, s situ) {
	// Should not node be Not label
	printNotNode("-----", buffer, s)
}

func (node NoCases) keyPress(ch rune, offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node NoCases) deleteCharachter(offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Perform) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("perform ", buffer, s)
	printLabel(node.label, buffer, info, s, effectStyle)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Perform) keyPress(ch rune, offset int) (Node, []int, int) {
	return labelKeyPress(node.label, ch, offset, func(s string) Node { return Perform{s} })
}

// This might only be perform and handle
// let never has label on the end
// select has ordering
func labelKeyPress(label string, ch rune, offset int, build func(string) Node) (Node, []int, int) {
	if offset == -1 {
		return build(label), []int{}, offset
	}
	if unicode.IsLetter(ch) || unicode.IsDigit(ch) {
		node := build(insertRune(label, offset, ch))
		return node, []int{}, offset + 1
	}
	if ch == '(' && offset == len(label) {
		return Call{build(label), Vacant{}}, []int{1}, 0
	}
	return build(label), []int{}, offset
}

func (node Perform) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Perform{label}, []int{}, offset
}

func (node Handle) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("handle ", buffer, s)
	printLabel(node.label, buffer, info, s, effectStyle)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Handle) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Handle{label}, []int{}, offset + 1
}

func (node Handle) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	return Handle{label}, []int{}, offset
}

func (node Builtin) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s, tcell.StyleDefault)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Builtin) keyPress(ch rune, offset int) (Node, []int, int) {

	if offset == -1 {
		return node, []int{}, 0
	}
	if unicode.IsLetter(ch) || unicode.IsDigit(ch) {
		label := insertRune(node.label, offset, ch)
		return Builtin{label}, []int{}, offset + 1
	}
	if ch == '(' && offset == node.contentLength() {
		return Call{node, Vacant{}}, []int{1}, 0
	}
	if ch == '.' && offset == node.contentLength() {
		return Call{Select{}, node}, []int{0}, 0
	}
	if ch == '=' && offset == node.contentLength() {
		// Sort of the same as control e
		return Let{node.label, Vacant{}, Vacant{}}, []int{0}, 0
	}

	return node, []int{}, offset
}

func (node Builtin) deleteCharachter(offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	label, offset := backspaceAt(node.label, offset)
	if label == "" {
		return Vacant{}, []int{}, offset
	}
	return Builtin{label}, []int{}, offset
}

func Print(node Node) ([]rendered, map[string]int) {
	buffer := []rendered{}
	info := make(map[string]int)
	node.print(&buffer, info, situ{path: []int{}})
	return buffer, info
}