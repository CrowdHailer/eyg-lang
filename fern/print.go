package fern

import (
	"fmt"
	"unicode"

	"github.com/gdamore/tcell/v2"
)

const blue3 = 0x87ceeb
const green4 = 0x7fbc8c
const orange4 = 0xff6b6b
const purple4 = 0x9723c9

var keywordStyle = tcell.StyleDefault.Dim(true)
var todoStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(orange4)).Bold(true)
var intStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(purple4))
var stringStyle = tcell.StyleDefault.Foreground(tcell.NewHexColor(green4))

// view exhibit rendered
// scene or panel page is the list of rendered
type rendered struct {
	character rune
	path      []int
	offset    int
	style     tcell.Style
}

func (node Fn) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.param, buffer, info, s)
	*buffer = append(*buffer, rendered{' ', s.path, len(node.param), keywordStyle})
	*buffer = append(*buffer, rendered{'-', s.path, -1, keywordStyle})
	*buffer = append(*buffer, rendered{'=', s.path, -1, keywordStyle})
	*buffer = append(*buffer, rendered{' ', s.path, -1, keywordStyle})
	node.body.print(buffer, info, situ{s.indent, true, false, append(s.path, 0)})
}

// Each node can have it's own interpretation of what -1 means but this is a public iterface for other nodes like call
// Keeping print and keypress together because of offsets but maybe not needed
func (node Fn) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, 0
	}
	param := insertRune(node.param, offset, ch)
	return Fn{param, node.body}, []int{}, offset + 1
}

func insertRune(s string, at int, new rune) string {
	return s[:at] + string(new) + s[at:]
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
				printLabel(group.label, buffer, info, situ{indent, false, false, append(path, 0, 0)})
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

func (node Call) print(buffer *[]rendered, info map[string]int, s situ) {
	// TODO switches not if - maybe not if is list is a fn on call
	if t, ok := node.fn.(Select); ok {
		node.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 1)})
		*buffer = append(*buffer, rendered{'.', s.path, 0, keywordStyle})

		printLabel(t.label, buffer, info, situ{s.indent, false, false, append(s.path, 0)})
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
			start := len(*buffer)
			*buffer = append(*buffer, rendered{'{', s.path, 0, keywordStyle})
			printLabel(t.label, buffer, info, situ{s.indent, false, false, append(s.path, 0, 0)})
			// comma doesn't work on expand
			*buffer = append(*buffer, rendered{':', s.path, 0, keywordStyle})
			*buffer = append(*buffer, rendered{' ', s.path, 0, keywordStyle})
			inner.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 0, 1)})
			printExtension(node.arg, buffer, info, append(s.path, 1), s.indent, s.nested, start)
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
	return node, []int{}, offset
}

func (node Var) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Var) keyPress(ch rune, offset int) (Node, []int, int) {

	if offset == -1 {
		return node, []int{}, 0
	}
	label := insertRune(node.label, offset, ch)
	return Var{label}, []int{}, offset + 1
}

// TODO take only path in args
func printLabel(label string, buffer *[]rendered, info map[string]int, s situ) {
	info[pathToString(s.path)] = len(*buffer)
	for i, ch := range label {
		*buffer = append(*buffer, rendered{ch, s.path, i, tcell.StyleDefault})
	}
}

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
		for i := 0; i < indent; i++ {
			*buffer = append(*buffer, rendered{' ', nil, -1, keywordStyle})
		}

		defer func() {
			// needs original depth indent
			for i := 0; i < s.indent; i++ {
				*buffer = append(*buffer, rendered{' ', nil, -1, keywordStyle})
			}
			*buffer = append(*buffer, rendered{'}', nil, -1, keywordStyle})
			*buffer = append(*buffer, rendered{'\n', nil, -1, keywordStyle})
		}()
	}
	printNotNode("let ", buffer, s)
	printLabel(node.label, buffer, info, s)
	*buffer = append(*buffer, rendered{' ', s.path, len(node.label), keywordStyle})
	*buffer = append(*buffer, rendered{'=', s.path, -1, keywordStyle})
	*buffer = append(*buffer, rendered{' ', s.path, -1, keywordStyle})
	node.value.print(buffer, info, situ{indent, false, true, append(s.path, 0)})
	// nested /false prints a new line
	for i := 0; i < indent; i++ {
		*buffer = append(*buffer, rendered{' ', nil, -1, keywordStyle})
	}
	node.then.print(buffer, info, situ{indent, false, false, append(s.path, 1)})
}

func (node Let) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Let{label, node.value, node.then}, []int{}, offset + 1
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
	switch ch {
	case '[':
		return Tail{}, []int{}, 0
	case '{':
		return Empty{}, []int{}, 0
	case '=':
		return Let{"", Vacant{}, Vacant{}}, []int{}, 0
	}
	if digit := ch - '0'; digit >= 0 && digit < 10 {
		return Integer{int(digit)}, []int{}, 1
	}
	if unicode.IsLetter(ch) {
		return Var{string(ch)}, []int{}, 1
	}
	return node, []int{}, 0
}

// TODO purple
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
	if offset == -1 {
		return node, []int{}, 0
	}
	// TODO real behaviour
	value := node.value * 10
	return Integer{value}, []int{}, offset + 1
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

func (node Cons) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("cons", buffer, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1, keywordStyle})
	}
}

func (node Cons) keyPress(ch rune, offset int) (Node, []int, int) {
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

func (node Extend) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("+", buffer, s)
	printLabel(node.label, buffer, info, s)
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

func (node Select) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode(".", buffer, s)
	printLabel(node.label, buffer, info, s)
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

func (node Overwrite) print(buffer *[]rendered, info map[string]int, s situ) {
	// is : better
	printNotNode("=", buffer, s)
	printLabel(node.label, buffer, info, s)
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

func (node Tag) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}

func (node Tag) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Tag{label}, []int{}, offset + 1
}

func (node Case) print(buffer *[]rendered, info map[string]int, s situ) {

}

func (node Case) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Case{label}, []int{}, offset + 1
}

func (node NoCases) print(buffer *[]rendered, info map[string]int, s situ) {

}

func (node NoCases) keyPress(ch rune, offset int) (Node, []int, int) {
	return node, []int{}, 0
}

func (node Perform) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("perform ", buffer, s)
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label), keywordStyle})
	}
}
func (node Perform) keyPress(ch rune, offset int) (Node, []int, int) {
	if offset == -1 {
		return node, []int{}, offset
	}
	label := insertRune(node.label, offset, ch)
	return Perform{label}, []int{}, offset + 1
}
func (node Handle) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("handle ", buffer, s)
	printLabel(node.label, buffer, info, s)
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

func Print(node Node) ([]rendered, map[string]int) {
	buffer := []rendered{}
	info := make(map[string]int)
	node.print(&buffer, info, situ{path: []int{}})
	return buffer, info
}
