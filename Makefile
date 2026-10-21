
OPENCODE_IMAGE = opencode-sandbox
CLAUDE_IMAGE = claude-sandbox
BIN_DIR = ~/.local/bin
SCRIPT = runner.sh
LINK_NAME = opencode
CLAUDE_LINK_NAME = claude

.PHONY: all build install bump-versions update clean

all: install

build:
	podman build --no-cache --target opencode -t $(OPENCODE_IMAGE) -f Containerfile .
	podman build --target claude -t $(CLAUDE_IMAGE) -f Containerfile .

install: build
	chmod +x $(SCRIPT)
	mkdir -p state claude_state
	ln -sf $(shell pwd)/$(SCRIPT) $(BIN_DIR)/$(LINK_NAME)
	ln -sf $(shell pwd)/$(SCRIPT) $(BIN_DIR)/$(CLAUDE_LINK_NAME)

bump-versions:
	@echo "Checking latest versions..."
	@GO_VER=$$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1); \
	if [ -n "$$GO_VER" ]; then sed -i "s/^ARG GO_VERSION=.*/ARG GO_VERSION=$$GO_VER/" Containerfile; echo "  Go:       $$GO_VER"; fi
	@ZIG_VER=$$(curl -fsSL https://ziglang.org/download/index.json | grep -E '^\s*"[0-9]+\.[0-9]+\.[0-9]+"\s*:' | head -n1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'); \
	if [ -n "$$ZIG_VER" ]; then sed -i "s/^ARG ZIG_VERSION=.*/ARG ZIG_VERSION=$$ZIG_VER/" Containerfile; echo "  Zig:      $$ZIG_VER"; fi
	@RUST_VER=$$(curl -fsSL https://static.rust-lang.org/dist/channel-rust-stable.toml | sed -n '/^\[pkg\.rustc\]/,/^\[/ s/^version = "\([0-9.]*\).*/\1/p'); \
	if [ -n "$$RUST_VER" ]; then sed -i "s/^ARG RUST_VERSION=.*/ARG RUST_VERSION=$$RUST_VER/" Containerfile; echo "  Rust:     $$RUST_VER"; fi
	@BUN_VER=$$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/oven-sh/bun/releases/latest | sed -n 's|.*/bun-v\([0-9.]*\)$$|\1|p'); \
	if [ -n "$$BUN_VER" ]; then sed -i "s/^ARG BUN_VERSION=.*/ARG BUN_VERSION=$$BUN_VER/" Containerfile; echo "  Bun:      $$BUN_VER"; fi
	@OC_VER=$$(curl -fsSL https://opencode.ai/update/api/latest/cli/npm | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'); \
	if [ -n "$$OC_VER" ]; then sed -i "s/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=$$OC_VER/" Containerfile; echo "  OpenCode: $$OC_VER"; fi
	@CL_VER=$$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest); \
	if [ -n "$$CL_VER" ]; then sed -i "s/^ARG CLAUDE_VERSION=.*/ARG CLAUDE_VERSION=$$CL_VER/" Containerfile; echo "  Claude:   $$CL_VER"; fi

update: bump-versions
	podman build --target opencode -t $(OPENCODE_IMAGE) -f Containerfile .
	podman build --target claude -t $(CLAUDE_IMAGE) -f Containerfile .

clean:
	rm -f $(BIN_DIR)/$(LINK_NAME) $(BIN_DIR)/$(CLAUDE_LINK_NAME)
	podman rmi $(OPENCODE_IMAGE) $(CLAUDE_IMAGE) || true
