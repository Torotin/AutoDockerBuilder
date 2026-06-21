FROM golang:1.26.3-alpine AS builder

WORKDIR /app

COPY go.mod .
COPY go.sum .

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 go build -o usque -ldflags="-s -w" .

# scratch is not enough here because register/enroll need a cert store.
FROM alpine:latest

RUN apk add --no-cache ca-certificates curl

WORKDIR /app

COPY --from=builder /app/usque /bin/usque
COPY DockerEntrypoint.sh /app/usque-entrypoint
RUN chmod +x /app/usque-entrypoint

EXPOSE 1080

ENTRYPOINT ["/app/usque-entrypoint"]
CMD ["socks"]
