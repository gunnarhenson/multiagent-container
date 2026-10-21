# opencode-container

This repository provides a sandboxed environment for running the `opencode` and `claude` (Claude Code) CLI tools inside a Podman container. It is designed to restrict local system and network access while providing a persistent configuration and isolated runtime.

## Features

- **Podman Sandbox:** Runs `opencode` or `claude` in an AlmaLinux-based container with strict resource limits (CPUs, memory, PIDs) and a read-only root filesystem.
- **Security & Privilege Drop:** Drops all capabilities by default (`--cap-drop=ALL`). The container's `entrypoint.sh` blocks access to local private IPv4 addresses (RFC 1918) via blackhole routing and drops remaining privileges using `setpriv --no-new-privs` before executing the CLI.
- **Workspace Mounting:** Mounts the current working directory of the host into the container's `/workspace`. Defaults to read-only (`ro`) mode, but can be configured as read-write via the `-rw` flag on the runner script. Additional directories can be mounted under `/mnt/<name>` using `-m`.
- **State Persistence:** Maintains agent state and configurations locally using host-mounted volumes (`state/`, `opencode.jsonc`, `opencode.gitignore` for OpenCode; `claude_state/`, `claude_settings.json` for Claude Code) ensuring history, credentials, and settings persist across container executions.

## Installation

A `Makefile` is provided to build the container image and install the runner script.

```bash
make install
```

This will:
1. Build the Podman images `opencode-sandbox` and `claude-sandbox` (sharing a common toolchain base stage) using the `Containerfile`.
2. Create the necessary `state` and `claude_state` directories.
3. Create symlinks from `runner.sh` to `~/.local/bin/opencode` and `~/.local/bin/claude`.

To fetch the latest upstream versions (Go, Zig, Rust, Bun, OpenCode, and Claude Code) and rebuild changed image layers:

```bash
make update
```

## Authentication & Configuration

### Claude Code

Because the container runs in an isolated network namespace without a local browser, interactive TUI browser callbacks (`localhost:<port>`) cannot automatically redirect from the host browser into the container. You can sign in and migrate your setup using any of the following methods:

#### 1. Copy Existing Host Login, Plugins & Settings (Recommended)
If you have already signed into Claude Code on your host machine:

```bash
# Copy credentials, installed plugins, skills, and state into claude_state/
cp -a ~/.claude/. ./claude_state/
cp ~/.claude.json ./claude_state/.claude.json

# Rewrite hardcoded host home paths in plugin manifests to the container user path
sed -i "s|${HOME}/.claude|/home/opencode-user/.claude|g" \
  ./claude_state/plugins/installed_plugins.json \
  ./claude_state/plugins/known_marketplaces.json 2>/dev/null || true
```

Merge any custom settings (such as `enabledPlugins` or `extraKnownMarketplaces` from `~/.claude/settings.json`) into `./claude_settings.json` while keeping the container's `permissions` block (`/mnt`, `/tmp`, and `.env` deny rules).

> **Note:** OAuth tokens in `claude_state/.credentials.json` auto-refresh inside the container. Avoid running a separate host `claude` installation against the same credentials in parallel, as OAuth refresh token rotation will invalidate the other copy.

#### 2. Sign In (or Re-Sign In) from Inside the Container
When you need to sign in or re-authenticate:

```bash
# Add -lan if your SSO/IdP requires internal corporate network/DNS access
claude auth login
```

1. Open the printed OAuth URL in your host browser (use `claude auth login` rather than the TUI `/login` box so terminal line-wrapping does not corrupt the URL).
2. Complete SSO in the browser and paste the returned authorization code into the terminal prompt.

#### 3. Environment Variables (`.env`)
`runner.sh` loads `.env` via `podman run --env-file` (use plain `KEY=VALUE` lines without `export` or quotes):

```env
# Long-lived OAuth token (generated via `claude setup-token`)
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Or direct API key
ANTHROPIC_API_KEY=sk-ant-api03-...
```

### OpenCode

Run `opencode` and use `/connect` (or `opencode auth login`), or add your provider API keys to `.env`. Credentials and state persist in `./state/` and configuration in `./opencode.jsonc`.

## Usage

Once installed, you can use the `opencode` and `claude` commands globally. They execute within the Podman container, mounting your current directory.

```bash
# Run opencode or claude with read-only access to the current directory
opencode
claude

# Run with read-write access to the current directory
opencode -rw [args...]
claude -rw [args...]

# Mount additional directories to /mnt/<dirname> (inherits container ro/rw mode by default)
opencode -m /path/to/dir1 -m /path/to/dir2
claude -m /path/to/dir1 -m /path/to/dir2

# Override permissions per mount (:ro or :rw) or set a custom mount name
opencode -rw -m /path/to/readonly-repo:ro -m /path/to/other:custom-name:rw
claude -rw -m /path/to/readonly-repo:ro -m /path/to/other:custom-name:rw
```
