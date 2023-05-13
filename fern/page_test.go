package fern

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestIndexToCoordinate(t *testing.T) {
	page := []rendered{
		{charachter: 'a'},
		{charachter: 'b'},
		{charachter: '\n'},
		{charachter: 'c'},
		{charachter: '\n'},
		{charachter: '\n'},
		{charachter: 'd'},
		{charachter: 'e'},
		{charachter: '\n'},
	}

	// screen 2x 2
	tests := []Coordinate{
		{0, 0},
		{1, 0},
		{2, 0},
		{0, 1},
		{1, 1},
		{0, 2},
		{0, 3},
		{1, 3},
		{2, 3},
	}
	assert.Equal(t, len(page), len(tests))
	for i, want := range tests {
		got := indexToCoordinate(page, i)
		assert.Equal(t, want, got)
	}
}
