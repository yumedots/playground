package main

import (
	"os"
	"testing"
)

func TestSpecialMode(t *testing.T) {
	cases := []struct {
		permissions uint64
		want        os.FileMode
	}{
		{0o4755, 0o755 | os.ModeSetuid},
		{0o6755, 0o755 | os.ModeSetuid | os.ModeSetgid},
		{0o2755, 0o755 | os.ModeSetgid},
		{0o1777, 0o777 | os.ModeSticky},
		{0o4711, 0o711 | os.ModeSetuid},
	}
	for _, test := range cases {
		if got := specialMode(test.permissions); got != test.want {
			t.Errorf("specialMode(%04o) = %v, want %v", test.permissions, got, test.want)
		}
	}
}
