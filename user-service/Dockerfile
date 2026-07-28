# syntax=docker/dockerfile:1
# ---------- build stage ----------
FROM golang:1.26-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/app ./cmd

# ---------- runtime stage (non-root, distroless) ----------
FROM gcr.io/distroless/static-debian12:nonroot
ENV SERVICE_NAME=user-service
COPY --from=build /bin/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
