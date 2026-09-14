# Makefile for Mole

.PHONY: all build clean check format test test-go verify release release-amd64 release-arm64 package-candidate mod-download

# Output directory
BIN_DIR := bin

# Go toolchain
GO ?= go
GO_DOWNLOAD_RETRIES ?= 3

# Binaries
ANALYZE := analyze
STATUS := status

# Source directories
ANALYZE_SRC := ./cmd/analyze
STATUS_SRC := ./cmd/status

# Build flags
LDFLAGS := -s -w
RELEASE_GO_ENV := CGO_ENABLED=0

all: build

# Download modules with retries to mitigate transient proxy/network EOF errors.
mod-download:
	@attempt=1; \
	while [ $$attempt -le $(GO_DOWNLOAD_RETRIES) ]; do \
		echo "Downloading Go modules ($$attempt/$(GO_DOWNLOAD_RETRIES))..."; \
		if $(GO) mod download; then \
			exit 0; \
		fi; \
		sleep $$((attempt * 2)); \
		attempt=$$((attempt + 1)); \
	done; \
	echo "Go module download failed after $(GO_DOWNLOAD_RETRIES) attempts"; \
	exit 1

# Local build (current architecture)
build:
	@echo "Building for local architecture..."
	GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off $(GO) build -mod=readonly -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-go $(ANALYZE_SRC)
	GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off $(GO) build -mod=readonly -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-go $(STATUS_SRC)

check:
	./scripts/check.sh --no-format

format:
	./scripts/check.sh --format

test:
	MOLE_TEST_NO_AUTH=1 ./scripts/test.sh

test-go:
	MOLE_TEST_NO_AUTH=1 bash scripts/test_sandbox.sh $(GO) test ./...

verify: check test-go

# New output paths only; never replace or publish an existing candidate.
package-candidate:
	@test -n "$(OUTPUT)" || { echo 'Usage: make package-candidate OUTPUT=/absolute/new/directory'; exit 1; }
	MOLE_TEST_NO_AUTH=1 bash scripts/test_sandbox.sh python3 scripts/package_release.py "$(OUTPUT)"

# Manual cross-builds only; these do not tag, upload or publish anything.
# Prepared dependencies are required. Keep pure-Go to avoid SDK-driven minOS changes.
release-amd64:
	@echo "Building release binaries (amd64)..."
	GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off $(RELEASE_GO_ENV) GOOS=darwin GOARCH=amd64 $(GO) build -mod=readonly -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-darwin-amd64 $(ANALYZE_SRC)
	GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off $(RELEASE_GO_ENV) GOOS=darwin GOARCH=amd64 $(GO) build -mod=readonly -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-darwin-amd64 $(STATUS_SRC)

release-arm64:
	@echo "Building release binaries (arm64)..."
	GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off $(RELEASE_GO_ENV) GOOS=darwin GOARCH=arm64 $(GO) build -mod=readonly -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-darwin-arm64 $(ANALYZE_SRC)
	GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off $(RELEASE_GO_ENV) GOOS=darwin GOARCH=arm64 $(GO) build -mod=readonly -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-darwin-arm64 $(STATUS_SRC)

clean:
	@echo "Cleaning binaries..."
	rm -f $(BIN_DIR)/$(ANALYZE)-* $(BIN_DIR)/$(STATUS)-* $(BIN_DIR)/$(ANALYZE)-go $(BIN_DIR)/$(STATUS)-go
