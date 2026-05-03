FROM golang:1.25.5-alpine AS builder

WORKDIR /app

COPY go.mod .
COPY go.sum .

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 go build -o usque -ldflags="-s -w" .

# scratch is not enough here because register/enroll need a cert store.
FROM alpine:latest

RUN apk add --no-cache ca-certificates

WORKDIR /data

COPY --from=builder /app/usque /bin/usque

EXPOSE 1080

ENTRYPOINT ["/bin/usque"]
CMD ["socks"]
