package fern

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPrinting(t *testing.T) {
	tests := []struct {
		source Node
		buffer []rendered
		info   map[string]int
	}{
		{
			Var{"x"},
			[]rendered{
				{'x', []int{}, 0},
				{'\n', []int{}, 1},
			},
			map[string]int{"[]": 0},
		},
		{
			Vacant{""},
			[]rendered{
				{'t', []int{}, 0},
				{'o', []int{}, 1},
				{'d', []int{}, 2},
				{'o', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 0},
		},
		{
			String{"hey"},
			[]rendered{
				{'"', []int{}, -1},
				{'h', []int{}, 0},
				{'e', []int{}, 1},
				{'y', []int{}, 2},
				{'"', []int{}, 3},
				{'\n', []int{}, -1},
			},
			map[string]int{"[]": 1},
		},
		{
			Integer{10},
			[]rendered{
				{'1', []int{}, 0},
				{'0', []int{}, 1},
				{'\n', []int{}, 2},
			},
			map[string]int{"[]": 0},
		},
		{
			Tail{},
			[]rendered{
				{'[', []int{}, -1},
				{']', []int{}, 0},
				{'\n', []int{}, -1},
			},
			map[string]int{"[]": 1},
		},
		{
			Select{"name"},
			[]rendered{
				{'.', []int{}, -1},
				{'n', []int{}, 0},
				{'a', []int{}, 1},
				{'m', []int{}, 2},
				{'e', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 1},
		},
		{
			Perform{"Log"},
			[]rendered{
				{'p', []int{}, -1},
				{'e', []int{}, -1},
				{'r', []int{}, -1},
				{'f', []int{}, -1},
				{'o', []int{}, -1},
				{'r', []int{}, -1},
				{'m', []int{}, -1},
				{' ', []int{}, -1},
				{'L', []int{}, 0},
				{'o', []int{}, 1},
				{'g', []int{}, 2},
				{'\n', []int{}, 3},
			},
			map[string]int{"[]": 8},
		},
		// Fn test
		{
			Call{Var{"x"}, String{""}},
			[]rendered{
				{'x', []int{0}, 0},
				{'(', []int{}, 0},
				{'"', []int{1}, -1},
				{'"', []int{1}, 0},
				{')', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		},
		{
			Call{Perform{"Log"}, Integer{5}},
			[]rendered{
				{'p', []int{0}, -1},
				{'e', []int{0}, -1},
				{'r', []int{0}, -1},
				{'f', []int{0}, -1},
				{'o', []int{0}, -1},
				{'r', []int{0}, -1},
				{'m', []int{0}, -1},
				{' ', []int{0}, -1},
				{'L', []int{0}, 0},
				{'o', []int{0}, 1},
				{'g', []int{0}, 2},
				{'(', []int{}, 0},
				{'5', []int{1}, 0},
				{')', []int{}, 2},
				{'\n', []int{}, 3},
			},
			map[string]int{"[]": 11, "[0]": 8, "[1]": 12},
		},
		{
			Call{Tag{"Ok"}, Var{"x"}},
			[]rendered{
				{'O', []int{0}, 0},
				{'k', []int{0}, 1},
				{'(', []int{}, 0},
				{'x', []int{1}, 0},
				{')', []int{}, 2},
				{'\n', []int{}, 3},
			},
			map[string]int{"[]": 2, "[0]": 0, "[1]": 3},
		},
		{
			Let{"a", Integer{1}, Let{"b", Integer{2}, Integer{3}}},
			[]rendered{
				{'l', []int{}, -1},
				{'e', []int{}, -1},
				{'t', []int{}, -1},
				{' ', []int{}, -1},
				{'a', []int{}, 0},
				{' ', []int{}, 1},
				{'=', []int{}, -1},
				{' ', []int{}, -1},
				{'1', []int{0}, 0},
				{'\n', []int{0}, 1},
				{'l', []int{1}, -1},
				{'e', []int{1}, -1},
				{'t', []int{1}, -1},
				{' ', []int{1}, -1},
				{'b', []int{1}, 0},
				{' ', []int{1}, 1},
				{'=', []int{1}, -1},
				{' ', []int{1}, -1},
				{'2', []int{1, 0}, 0},
				{'\n', []int{1, 0}, 1},
				{'3', []int{1, 1}, 0},
				{'\n', []int{1, 1}, 1},
			},
			map[string]int{"[]": 4, "[0]": 8, "[1]": 14, "[1,0]": 18, "[1,1]": 20},
		},
		{
			Let{"a", Let{"b", Integer{1}, Integer{2}}, Integer{3}},
			[]rendered{
				{'l', []int{}, -1},
				{'e', []int{}, -1},
				{'t', []int{}, -1},
				{' ', []int{}, -1},
				{'a', []int{}, 0},
				{' ', []int{}, 1},
				{'=', []int{}, -1},
				{' ', []int{}, -1},
				{'{', nil, -1},
				{'\n', nil, -1},
				{' ', nil, -1},
				{' ', nil, -1},
				{'l', []int{0}, -1},
				{'e', []int{0}, -1},
				{'t', []int{0}, -1},
				{' ', []int{0}, -1},
				{'b', []int{0}, 0},
				{' ', []int{0}, 1},
				{'=', []int{0}, -1},
				{' ', []int{0}, -1},
				{'1', []int{0, 0}, 0},
				{'\n', []int{0, 0}, 1},
				{' ', nil, -1},
				{' ', nil, -1},
				{'2', []int{0, 1}, 0},
				{'\n', []int{0, 1}, 1},
				{'}', nil, -1},
				{'\n', nil, -1},
				{'3', []int{1}, 0},
				{'\n', []int{1}, 1},
			},
			map[string]int{"[]": 4, "[0]": 16, "[0,0]": 20, "[0,1]": 24, "[1]": 28},
		},
		// Sugar
		{
			// buld comma where
			// [1, ]
			// [1, ..x]
			// , needs to be on call because may be block
			// [{ .. }, 2]
			// only top element and tail clickable
			// press comma on brackets can't go into string because quotes separate but numbers can extend number
			// [x] comma on tail -> [x, hole]
			// [] comma on tail -> [hole]
			// [a, b] comma on comma -> [a, hole, b] where what your on becomes is the call stack
			Call{Call{Cons{}, Integer{1}}, Call{Call{Cons{}, Integer{2}}, Tail{}}},
			[]rendered{
				{'[', []int{}, 0},
				{'1', []int{0, 1}, 0},
				{',', []int{1}, 0},
				{' ', []int{1}, 1},
				// Nothing is zero widith so can check if at tail with offset > 2
				// can start with '[' or ', '
				{'2', []int{1, 0, 1}, 0}, // comma on number can make a list because that would be list in list
				// make this one because try and not go up the list for edits
				{']', []int{1}, 3}, // or should this be the call above with offset for insert
				{'\n', []int{1}, 4},
			},
			map[string]int{"[0,1]": 1, "[1,0,1]": 4},
		},
		{
			Call{Var{"x"}, Tail{}},
			[]rendered{
				{'x', []int{0}, 0},
				{'(', []int{}, 0},
				{'[', []int{1}, -1},
				{']', []int{1}, 0},
				{')', []int{}, 3},
				{'\n', []int{}, 4},
			},
			map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		},
		// {
		// 	Call{Call{Cons{}, Var{"x"}}, Var{"y"}},
		// 	[]rendered{
		// 		{'[', []int{}, 0},
		// 		{'x', []int{1, 0}, 0},
		// 		{',', []int{1}, -1},
		// 		{' ', []int{1}, 0},
		// 		{'.', []int{1}, 3},
		// 		{'.', []int{1}, 3},
		// 		// TODO Doesn't work with offset in var an in tail at the same time
		// 		// should call always be -1 it's a text thing after all
		// 		// Only need is differationation between before and after
		// 		{'y', []int{1}, 3},
		// 		{']', []int{1}, 3},
		// 		{'\n', []int{1}, 4},
		// 	},
		// 	map[string]int{"[]": 1, "[0]": 0, "[1]": 3},
		// },
		{
			Call{Select{"a"}, Var{"x"}},
			[]rendered{
				{'x', []int{1}, 0},
				// Don't have any reference to call node but this is ok - Nope
				// Needs to be ref to call node because arg might be a block or other
				{'.', []int{}, 0},
				{'a', []int{0}, 0},
				{'\n', []int{0}, 1},
			},
			map[string]int{"[1]": 0, "[0]": 2},
		},
		// TODO case statement
	}

	for _, tt := range tests {
		rendered, info := Print(tt.source)

		assertRendered(t, tt.buffer, rendered)
		assert.Equal(t, tt.info, info)
	}
}

func assertRendered(t *testing.T, expected, actual []rendered) {
	expectedText := renderedText(expected)
	actualText := renderedText(actual)
	if expectedText != actualText {
		t.Logf("Not equal:\nexpected: %s\nactual:   %s", expectedText, actualText)
		t.Fail()
	}

	expectedPaths := renderedPaths(expected)
	actualPaths := renderedPaths(actual)
	assert.Equal(t, expectedPaths, actualPaths)

	expectedOffsets := renderedOffsets(expected)
	actualOffsets := renderedOffsets(actual)
	assert.Equal(t, expectedOffsets, actualOffsets)
}

func renderedText(buffer []rendered) string {
	out := ""
	for _, r := range buffer {
		out += string(r.charachter)
	}
	// Shows newline charachters
	return fmt.Sprintf("%#v", out)
}

func renderedPaths(buffer []rendered) []string {
	var out []string
	for _, r := range buffer {
		out = append(out, pathToString(r.path))
	}
	return out
}

func renderedOffsets(buffer []rendered) []int {
	var out []int
	for _, r := range buffer {
		out = append(out, r.offset)
	}
	return out
}
