package fern

import (
	"fmt"
)

func (node Fn) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.param, buffer, info, s)
	*buffer = append(*buffer, rendered{' ', s.path, len(node.param)})
	*buffer = append(*buffer, rendered{'-', s.path, -1})
	*buffer = append(*buffer, rendered{'=', s.path, -1})
	*buffer = append(*buffer, rendered{' ', s.path, -1})
	node.body.print(buffer, info, situ{s.indent, true, false, append(s.path, 0)})
}

func printTail(node Node, buffer *[]rendered, info map[string]int, path []int, indent int, nested bool, start int) {
	switch t := node.(type) {
	case Call:
		// TODO wrap up this switching to a fn on call
		if inner, ok := t.fn.(Call); ok {
			if _, ok := inner.fn.(Cons); ok {
				start := len(*buffer)
				*buffer = append(*buffer, rendered{',', path, 0})
				*buffer = append(*buffer, rendered{' ', path, 1})
				inner.arg.print(buffer, info, situ{indent, true, true, append(path, 0, 1)})
				printTail(t.arg, buffer, info, path, indent, nested, start)
			}
		}
		return
	case Tail:
		offset := len(*buffer) - start
		*buffer = append(*buffer, rendered{']', path, offset})
		if !nested {
			*buffer = append(*buffer, rendered{'\n', path, offset + 1})
		}
		return
	}
	start2 := len(*buffer)
	// Pressing comma on this makes a list in the tail position which is what we want
	// there is no choice between at element or tail position because it is not yet a lets itself.
	*buffer = append(*buffer, rendered{',', path, 0})
	*buffer = append(*buffer, rendered{' ', path, 1})
	*buffer = append(*buffer, rendered{'.', path, 2})
	*buffer = append(*buffer, rendered{'.', path, 3})
	node.print(buffer, info, situ{indent, true, true, path})
	offset := len(*buffer) - start2
	*buffer = append(*buffer, rendered{']', path, offset})
	if !nested {
		*buffer = append(*buffer, rendered{'\n', path, offset + 1})
	}

}

func (node Call) print(buffer *[]rendered, info map[string]int, s situ) {
	if t, ok := node.fn.(Select); ok {
		node.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 1)})
		*buffer = append(*buffer, rendered{'.', s.path, 0})

		printLabel(t.label, buffer, info, situ{s.indent, false, false, append(s.path, 0)})
		if !s.nested {
			*buffer = append(*buffer, rendered{'\n', append(s.path, 0), len(t.label)})
		}
		return
	}
	if inner, ok := node.fn.(Call); ok {
		// TODO switches not if
		if _, ok := inner.fn.(Cons); ok {
			start := len(*buffer)
			*buffer = append(*buffer, rendered{'[', s.path, 0})
			inner.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 0, 1)})
			printTail(node.arg, buffer, info, append(s.path, 1), s.indent, s.nested, start)
			return
		}

	}

	node.fn.print(buffer, info, situ{s.indent, true, true, append(s.path, 0)})
	start := len(*buffer)
	info[pathToString(s.path)] = start

	*buffer = append(*buffer, rendered{'(', s.path, 0})
	node.arg.print(buffer, info, situ{s.indent, true, true, append(s.path, 1)})
	offset := len(*buffer) - start
	*buffer = append(*buffer, rendered{')', s.path, offset})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, offset + 1})
	}
}

func (node Var) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}

// TODO take only path in args
func printLabel(label string, buffer *[]rendered, info map[string]int, s situ) {
	info[pathToString(s.path)] = len(*buffer)
	for i, ch := range label {
		*buffer = append(*buffer, rendered{ch, s.path, i})
	}
}

func printNotNode(content string, buffer *[]rendered, s situ) {
	for _, ch := range content {
		*buffer = append(*buffer, rendered{ch, s.path, -1})
	}
}

func (node Let) print(buffer *[]rendered, info map[string]int, s situ) {
	indent := s.indent
	if s.block {
		indent += 2
		*buffer = append(*buffer, rendered{'{', nil, -1})
		*buffer = append(*buffer, rendered{'\n', nil, -1})
		for i := 0; i < indent; i++ {
			*buffer = append(*buffer, rendered{' ', nil, -1})
		}

		defer func() {
			// needs original depth indent
			for i := 0; i < s.indent; i++ {
				*buffer = append(*buffer, rendered{' ', nil, -1})
			}
			*buffer = append(*buffer, rendered{'}', nil, -1})
			*buffer = append(*buffer, rendered{'\n', nil, -1})
		}()
	}
	printNotNode("let ", buffer, s)
	printLabel(node.label, buffer, info, s)
	*buffer = append(*buffer, rendered{' ', s.path, len(node.label)})
	*buffer = append(*buffer, rendered{'=', s.path, -1})
	*buffer = append(*buffer, rendered{' ', s.path, -1})
	node.value.print(buffer, info, situ{indent, false, true, append(s.path, 0)})
	// nested /false prints a new line
	for i := 0; i < indent; i++ {
		*buffer = append(*buffer, rendered{' ', nil, -1})
	}
	node.then.print(buffer, info, situ{indent, false, false, append(s.path, 1)})
}

// TODO red
func (node Vacant) print(buffer *[]rendered, info map[string]int, s situ) {
	info[pathToString(s.path)] = len(*buffer)
	content := node.note
	if content == "" {
		content = "todo"
	}
	for i, ch := range content {
		*buffer = append(*buffer, rendered{ch, s.path, i})
	}
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(content)})
	}
}

// TODO purple
func (node Integer) print(buffer *[]rendered, info map[string]int, s situ) {
	info[pathToString(s.path)] = len(*buffer)
	content := fmt.Sprintf("%d", node.value)
	for i, ch := range content {
		*buffer = append(*buffer, rendered{ch, s.path, i})
	}
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(content)})
	}
}

// Does this need to be *buffer
func (node String) print(buffer *[]rendered, info map[string]int, s situ) {
	*buffer = append(*buffer, rendered{'"', s.path, -1})
	// start of active, maybe origin is a better name
	info[pathToString(s.path)] = len(*buffer)
	for i, ch := range node.value {
		*buffer = append(*buffer, rendered{ch, s.path, i})
	}
	*buffer = append(*buffer, rendered{'"', s.path, len(node.value)})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1})
	}
}

func (node Tail) print(buffer *[]rendered, info map[string]int, s situ) {
	*buffer = append(*buffer, rendered{'[', s.path, -1})
	info[pathToString(s.path)] = len(*buffer)
	*buffer = append(*buffer, rendered{']', s.path, 0})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1})
	}
}

func (node Cons) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("cons", buffer, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1})
	}
}

func (node Empty) print(buffer *[]rendered, info map[string]int, s situ) {
	*buffer = append(*buffer, rendered{'{', s.path, -1})
	info[pathToString(s.path)] = len(*buffer)
	*buffer = append(*buffer, rendered{'}', s.path, 0})
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, -1})
	}
}

func (node Extend) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("+", buffer, s)
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}

func (node Select) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode(".", buffer, s)
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}

func (node Overwrite) print(buffer *[]rendered, info map[string]int, s situ) {
	// is : better
	printNotNode("=", buffer, s)
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}

func (node Tag) print(buffer *[]rendered, info map[string]int, s situ) {
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}
func (node Case) print(buffer *[]rendered, info map[string]int, s situ) {

}
func (node NoCases) print(buffer *[]rendered, info map[string]int, s situ) {

}
func (node Perform) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("perform ", buffer, s)
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}
func (node Handle) print(buffer *[]rendered, info map[string]int, s situ) {
	printNotNode("handle ", buffer, s)
	printLabel(node.label, buffer, info, s)
	if !s.nested {
		*buffer = append(*buffer, rendered{'\n', s.path, len(node.label)})
	}
}

func Print(node Node) ([]rendered, map[string]int) {
	buffer := []rendered{}
	info := make(map[string]int)
	node.print(&buffer, info, situ{path: []int{}})
	return buffer, info
}
