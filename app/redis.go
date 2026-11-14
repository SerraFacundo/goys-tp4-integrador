package main

// Cliente RESP mínimo: solo los comandos que usa la app (AUTH, PING, LPUSH,
// LTRIM, LRANGE). Evita una dependencia externa y deja la imagen sin
// librerías de terceros para escanear.

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"time"
)

type redisConn struct {
	conn net.Conn
	r    *bufio.Reader
}

// dialRedis abre una conexión y se autentica si hay contraseña.
func dialRedis(addr, password string) (*redisConn, error) {
	c, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		return nil, err
	}
	c.SetDeadline(time.Now().Add(5 * time.Second))
	rc := &redisConn{conn: c, r: bufio.NewReader(c)}
	if password != "" {
		if _, err := rc.do("AUTH", password); err != nil {
			c.Close()
			return nil, err
		}
	}
	return rc, nil
}

func (rc *redisConn) Close() error { return rc.conn.Close() }

func (rc *redisConn) do(args ...string) (any, error) {
	if _, err := rc.conn.Write(encodeCommand(args)); err != nil {
		return nil, err
	}
	return readReply(rc.r)
}

func encodeCommand(args []string) []byte {
	b := fmt.Appendf(nil, "*%d\r\n", len(args))
	for _, a := range args {
		b = fmt.Appendf(b, "$%d\r\n%s\r\n", len(a), a)
	}
	return b
}

// readReply devuelve string, int64, nil (bulk nulo) o []any.
func readReply(r *bufio.Reader) (any, error) {
	line, err := r.ReadString('\n')
	if err != nil {
		return nil, err
	}
	if len(line) < 3 || line[len(line)-2] != '\r' {
		return nil, errors.New("redis: respuesta mal formada")
	}
	kind, body := line[0], line[1:len(line)-2]
	switch kind {
	case '+':
		return body, nil
	case '-':
		return nil, errors.New("redis: " + body)
	case ':':
		return strconv.ParseInt(body, 10, 64)
	case '$':
		n, err := strconv.Atoi(body)
		if err != nil {
			return nil, err
		}
		if n < 0 {
			return nil, nil
		}
		buf := make([]byte, n+2)
		if _, err := io.ReadFull(r, buf); err != nil {
			return nil, err
		}
		return string(buf[:n]), nil
	case '*':
		n, err := strconv.Atoi(body)
		if err != nil {
			return nil, err
		}
		if n < 0 {
			return nil, nil
		}
		items := make([]any, n)
		for i := range items {
			if items[i], err = readReply(r); err != nil {
				return nil, err
			}
		}
		return items, nil
	}
	return nil, fmt.Errorf("redis: tipo de respuesta desconocido %q", kind)
}
