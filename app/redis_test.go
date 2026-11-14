package main

import (
	"bufio"
	"reflect"
	"strings"
	"testing"
)

func TestEncodeCommand(t *testing.T) {
	got := string(encodeCommand([]string{"LPUSH", "mensajes", "hola"}))
	want := "*3\r\n$5\r\nLPUSH\r\n$8\r\nmensajes\r\n$4\r\nhola\r\n"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestReadReply(t *testing.T) {
	cases := []struct {
		in      string
		want    any
		wantErr bool
	}{
		{"+OK\r\n", "OK", false},
		{":3\r\n", int64(3), false},
		{"$4\r\nhola\r\n", "hola", false},
		{"$-1\r\n", nil, false},
		{"*2\r\n$1\r\na\r\n$2\r\nbc\r\n", []any{"a", "bc"}, false},
		{"*0\r\n", []any{}, false},
		{"-WRONGPASS invalid password\r\n", nil, true},
		{"?raro\r\n", nil, true},
		{"$10\r\ncorto\r\n", nil, true},
	}
	for _, c := range cases {
		got, err := readReply(bufio.NewReader(strings.NewReader(c.in)))
		if (err != nil) != c.wantErr {
			t.Errorf("%q: err = %v, wantErr %v", c.in, err, c.wantErr)
			continue
		}
		if !c.wantErr && !reflect.DeepEqual(got, c.want) {
			t.Errorf("%q: got %#v, want %#v", c.in, got, c.want)
		}
	}
}
