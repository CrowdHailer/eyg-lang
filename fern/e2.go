package fern

import (
	"fmt"
	"strings"

	"github.com/gdamore/tcell/v2"
)

// view exhibit rendered
// scene or panel page is the list of rendered
type rendered struct {
	charachter rune
	style      tcell.Style
	node       *int
	offset     *int
}

// context i.e. context free grammer
// situation, surroundings
// location
// site
// position as in tail position

// ident path mode all needed, (block list)(sugar) also
// linear iteration a real pain for call
func (let Let) render() []rendered {
	// boundingBox := situation.column, + var length + 1
	for _, ch := range "let " {
		fmt.Println(ch)
	}
	return nil
}

func (call Call) render() {
	strings.Count("abc", "\n")
	var f []rune
	// arg := "hell0"
	// var x []rune
	var a rune
	_ = append(f, a, a)
}

// linear walk through level on a line depth = new line and reduce ident
// pass in *path if there render return cursor
// dont pass in cursor if we delete from offset position that indicates selecting the node move to selected and path
// if we delete use path for new cursor
// arrow keys or escape exit

type situ struct {
	indent int
	nested bool
	block  bool
}

// state with count, output, and mapping to info
// len(info = count)
// separate focus from highlight
func (string_ String) render(situ situ, focus []int, output []rendered) ([]rendered, []string) {
	// make a new pusher with offset counter inside
	zero := 0
	output = append(output, rendered{charachter: '"', offset: &zero})
	start := len(output)
	// if targeted(focus) {
	// }
	for i, ch := range string_.value {
		offset := i + 1
		output = append(output, rendered{charachter: ch, offset: &offset})
	}
	output = append(output, rendered{charachter: '"'})
	if !situ.nested {
		output = append(output, rendered{charachter: '\n'})
	}
	start := len(output)

	return nil, nil
}

// y = count newlines
// x = count back to newline

func inner(focus []int, child int) []int {
	// catches focus nil I believe
	if len(focus) == 0 || focus[0] != child {
		return nil
	}
	return focus[1:]
}

func targeted(focus []int) bool {
	if focus != nil || len(focus) == 0 {
		return true
	}
	return false
}
