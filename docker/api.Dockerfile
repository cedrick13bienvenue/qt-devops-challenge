FROM golang:1.23-alpine AS build
WORKDIR /src
COPY app/backend/go.mod app/backend/go.sum ./
RUN go mod download
COPY app/backend/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/projecthub-api .

FROM alpine:3.22
RUN adduser -D -H -u 10001 app
COPY --from=build /out/projecthub-api /usr/local/bin/projecthub-api
USER app
EXPOSE 8080
ENTRYPOINT ["projecthub-api"]
