# Bases fijadas por versión y digest: el build no cambia si se actualiza el tag.
FROM docker.io/library/golang:1.27-alpine@sha256:ea30e25680a5470bac02b08bb0e0a735fb75bd0ab7d431b9b95ee0abef362586 AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN go test ./... && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/app .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:52dcfbabb7457ea47c82f6e13af8c8a4a1d9f7b0145142b3ecab20f2b888411d
LABEL org.opencontainers.image.source="https://github.com/SerraFacundo/goys-tp4-integrador" \
      org.opencontainers.image.description="App X: libro de visitas de la Feria de Redes (GOYS)"
COPY --from=build /out/app /app
USER 10001:10001
EXPOSE 8080
# distroless no tiene shell ni curl: el binario consulta su propio /healthz.
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["/app", "-healthcheck"]
ENTRYPOINT ["/app"]
