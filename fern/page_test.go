package fern

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestIndexToCoordinate(t *testing.T) {
	rendered := []rendered{
		{character: 'a'},
		{character: 'b'},
		{character: '\n'},
		{character: 'c'},
		{character: '\n'},
		{character: '\n'},
		{character: 'd'},
		{character: 'e'},
		{character: '\n'},
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
	assert.Equal(t, len(rendered), len(tests))
	page := NewPage(rendered)
	assert.Equal(t, 3, page.size.X)
	assert.Equal(t, 4, page.size.Y)
	for i, want := range tests {
		got := page.coordinates[i]
		assert.Equal(t, want, got)

		assert.Equal(t, rendered[i].character, page.lookup[got.X][got.Y].character)
	}
}
