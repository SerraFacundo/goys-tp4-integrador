// App X: libro de visitas de la Feria. Ver docs/07-app.md.
package main

import (
	"flag"
	"html/template"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	listKey     = "mensajes"
	maxMensajes = 100 // Redis guarda solo los últimos 100
	maxLargo    = 280
)

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Libro de visitas · GOYS</title>
<style>body{font-family:sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem}li{margin:.5rem 0}</style>
</head>
<body>
<h1>Libro de visitas de la Feria de Redes</h1>
<form method="post" action="/mensajes">
<label for="texto">Dejá tu mensaje</label><br>
<textarea id="texto" name="texto" maxlength="280" rows="3" cols="40" required></textarea><br>
<button type="submit">Enviar</button>
</form>
<h2>Últimos mensajes</h2>
<ul>{{range .}}<li>{{.}}</li>{{else}}<li>Todavía no hay mensajes.</li>{{end}}</ul>
</body>
</html>`))

type app struct {
	redisAddr, redisPassword string
}

func main() {
	healthcheck := flag.Bool("healthcheck", false, "consulta /healthz y sale con 0 si responde 200")
	flag.Parse()

	port := env("PORT", "8080")
	if *healthcheck {
		// La imagen distroless no tiene shell ni curl: el binario se chequea a sí mismo.
		c := http.Client{Timeout: 2 * time.Second}
		resp, err := c.Get("http://127.0.0.1:" + port + "/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	a := &app{redisAddr: env("REDIS_ADDR", "redis:6379"), redisPassword: os.Getenv("REDIS_PASSWORD")}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", a.index)
	mux.HandleFunc("POST /mensajes", a.crear)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok\n")) })

	srv := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	log.Printf("escuchando en :%s, redis en %s", port, a.redisAddr)
	log.Fatal(srv.ListenAndServe())
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// shortcut: una conexión a Redis por pedido; usar un pool si hay mucho tráfico.
func (a *app) index(w http.ResponseWriter, r *http.Request) {
	rc, err := dialRedis(a.redisAddr, a.redisPassword)
	if err != nil {
		redisError(w, err)
		return
	}
	defer rc.Close()
	reply, err := rc.do("LRANGE", listKey, "0", "19")
	if err != nil {
		redisError(w, err)
		return
	}
	var msgs []string
	items, _ := reply.([]any)
	for _, it := range items {
		if s, ok := it.(string); ok {
			msgs = append(msgs, s)
		}
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	page.Execute(w, msgs) // html/template escapa el texto de los visitantes
}

func (a *app) crear(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	texto := strings.TrimSpace(r.FormValue("texto"))
	if texto == "" || !utf8.ValidString(texto) || utf8.RuneCountInString(texto) > maxLargo {
		http.Error(w, "El mensaje debe tener entre 1 y 280 caracteres.", http.StatusBadRequest)
		return
	}
	rc, err := dialRedis(a.redisAddr, a.redisPassword)
	if err != nil {
		redisError(w, err)
		return
	}
	defer rc.Close()
	if _, err := rc.do("LPUSH", listKey, texto); err != nil {
		redisError(w, err)
		return
	}
	if _, err := rc.do("LTRIM", listKey, "0", strconv.Itoa(maxMensajes-1)); err != nil {
		redisError(w, err)
		return
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func redisError(w http.ResponseWriter, err error) {
	log.Printf("redis: %v", err)
	http.Error(w, "No se pudo acceder a la base de mensajes.", http.StatusServiceUnavailable)
}
