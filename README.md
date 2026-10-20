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

To fetch the latest upstream versions (Go, Zig, Rust, OpenCode, and Claude Code) and rebuild changed image layers:

```bash
make update
```

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
