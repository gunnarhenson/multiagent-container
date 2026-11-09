#!/usr/bin/env bash

WORKSPACE_MODE="ro"
ARGS=()
EXTRA_MOUNT_SPECS=()

AGENT="opencode"
if [ "$(basename -- "$0")" = "claude" ]; then
  AGENT="claude"
fi

ALLOW_INTERNAL_IPS="0"
SHOW_WRAPPER_HELP="0"
while [ $# -gt 0 ]; do
  case "$1" in
    -rw)
      WORKSPACE_MODE="rw"
      shift
      ;;
    -lan)
      ALLOW_INTERNAL_IPS="1"
      shift
      ;;
    -claude|--claude)
      AGENT="claude"
      shift
      ;;
    -opencode|--opencode)
      AGENT="opencode"
      shift
      ;;
    -m)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "Error: -m requires a directory argument (e.g. -m /path/to/dir[:ro|rw])" >&2
        exit 1
      fi
      EXTRA_MOUNT_SPECS+=("$2")
      shift 2
      ;;
    -m=*)
      EXTRA_MOUNT_SPECS+=("${1#-m=}")
      shift
      ;;
    -h|--help|help)
      SHOW_WRAPPER_HELP="1"
      ARGS+=("--help")
      shift
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

WORKSPACE_DIR="$(pwd)"
FINAL_ARGS=()
SKIP_NEXT="0"
SEEN_SUBCOMMAND="0"

for arg in "${ARGS[@]}"; do
  if [ "$SKIP_NEXT" = "1" ]; then
    FINAL_ARGS+=("$arg")
    SKIP_NEXT="0"
    continue
  fi

  if [ "$AGENT" = "opencode" ]; then
    case "$arg" in
      --server|--session|-s|--prompt|--completions|--log-level|--model|--agent|--format|--file|-f|--title|--replay-limit)
        FINAL_ARGS+=("$arg")
        SKIP_NEXT="1"
        continue
        ;;
      -*)
        FINAL_ARGS+=("$arg")
        continue
        ;;
    esac

    if [ "$SEEN_SUBCOMMAND" = "0" ]; then
      case "$arg" in
        upgrade|update|uninstall|acp|api|debug|auth|mcp|plugin|models|stats|mini|run|session|service|reload|pair|serve)
          SEEN_SUBCOMMAND="1"
          FINAL_ARGS+=("$arg")
          continue
          ;;
      esac

      if [ -d "$arg" ]; then
        WORKSPACE_DIR=$(realpath -- "$arg")
        FINAL_ARGS+=(".")
        continue
      else
        echo "Error: workspace directory does not exist: ${arg}" >&2
        exit 1
      fi
    fi
  elif [ "$AGENT" = "claude" ]; then
    case "$arg" in
      --model|--effort|--permission-mode|--add-dir|--agent|--agents|--allowedTools|--allowed-tools|--disallowedTools|--disallowed-tools|--mcp-config|--system-prompt|--append-system-prompt|--output-format|--input-format|--max-turns|--session-id|--settings|--setting-sources|--betas|--plugin-dir|--file|-p|--print)
        FINAL_ARGS+=("$arg")
        SKIP_NEXT="1"
        continue
        ;;
      -*)
        FINAL_ARGS+=("$arg")
        continue
        ;;
    esac

    if [ "$SEEN_SUBCOMMAND" = "0" ]; then
      case "$arg" in
        auth|doctor|install|mcp|plugin|plugins|setup-token|update|upgrade|agents|auto-mode)
          SEEN_SUBCOMMAND="1"
          FINAL_ARGS+=("$arg")
          continue
          ;;
      esac

      if [ -d "$arg" ]; then
        WORKSPACE_DIR=$(realpath -- "$arg")
        continue
      fi
    fi
  fi

  FINAL_ARGS+=("$arg")
done
ARGS=("${FINAL_ARGS[@]}")

if [ "$WORKSPACE_MODE" = "rw" ]; then
  echo "starting ${AGENT} in rw mode"
fi
if [ "$ALLOW_INTERNAL_IPS" = "1" ]; then
  echo "starting ${AGENT} with internal network access"
fi

SCRIPT_DIR=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")

mkdir -p "${SCRIPT_DIR}/state" \
         "${SCRIPT_DIR}/claude_state/xdg_config/anthropic" \
         "${SCRIPT_DIR}/claude_state/xdg_state" \
         "${SCRIPT_DIR}/claude_state/ccstatusline"

ln -sfn /home/opencode-user/.claude/ccstatusline "${SCRIPT_DIR}/claude_state/xdg_config/ccstatusline"

if [ ! -f "${SCRIPT_DIR}/claude_state/ccstatusline/settings.json" ] && [ -f "${HOME}/.config/ccstatusline/settings.json" ]; then
    cp "${HOME}/.config/ccstatusline/settings.json" "${SCRIPT_DIR}/claude_state/ccstatusline/settings.json"
fi

if [ ! -f "${SCRIPT_DIR}/opencode.jsonc" ]; then
    touch "${SCRIPT_DIR}/opencode.jsonc"
fi

if [ ! -f "${SCRIPT_DIR}/claude_state/settings.json" ]; then
    if [ -f "${SCRIPT_DIR}/claude_settings.json" ] && [ ! -L "${SCRIPT_DIR}/claude_settings.json" ]; then
        mv "${SCRIPT_DIR}/claude_settings.json" "${SCRIPT_DIR}/claude_state/settings.json"
    else
        cat << 'EOF' > "${SCRIPT_DIR}/claude_state/settings.json"
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "additionalDirectories": [
      "/mnt",
      "/tmp"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)"
    ]
  }
}
EOF
    fi
fi

if [ ! -L "${SCRIPT_DIR}/claude_settings.json" ]; then
    ln -sfn claude_state/settings.json "${SCRIPT_DIR}/claude_settings.json"
fi

if [ ! -f "${SCRIPT_DIR}/.env" ]; then
    touch "${SCRIPT_DIR}/.env"
fi

RULES_RO="${SCRIPT_DIR}/state/RULES_RO.md"
RULES_RW="${SCRIPT_DIR}/state/RULES_RW.md"

if [ ! -f "$RULES_RO" ]; then
  cat << 'EOF' > "$RULES_RO"
# SYSTEM RULES
- Environment: You are running inside an isolated Podman container.
- Write access: `/tmp` ONLY. `/workspace` and all other paths are READ-ONLY.
- CRITICAL: `.git` is set to READ-ONLY by the OS. Do not attempt commits, pushes, or writes. Only use read commands.
EOF
fi

if [ ! -f "$RULES_RW" ]; then
  cat << 'EOF' > "$RULES_RW"
# SYSTEM RULES
- Environment: You are running inside an isolated Podman container.
- Write access: `/workspace` and `/tmp` ONLY. All other paths are READ-ONLY.
- CRITICAL: `.git` is set to READ-ONLY by the OS. Do not attempt commits, pushes, or writes. Only use read commands.
EOF
fi

PODMAN_MOUNTS=()
MOUNTED_GIT_DIRS=()

mount_git_dir_once() {
  local dir="$1"
  local existing
  for existing in "${MOUNTED_GIT_DIRS[@]}"; do
    if [ "$existing" = "$dir" ]; then
      return 0
    fi
  done
  MOUNTED_GIT_DIRS+=("$dir")
  PODMAN_MOUNTS+=("-v" "${dir}:${dir}:ro,z")
}

mount_git_ro() {
  local host_dir="$1"
  local container_dir="$2"

  if [ ! -e "${host_dir}/.git" ]; then
    return 0
  fi

  if [ -d "${host_dir}/.git" ]; then
    PODMAN_MOUNTS+=("-v" "${host_dir}/.git:${container_dir}/.git:ro,z")
    return 0
  fi

  if [ -f "${host_dir}/.git" ]; then
    local gitdir_line raw_gitdir wt_git_dir commondir_line common_git_dir
    IFS= read -r gitdir_line < "${host_dir}/.git" || true
    gitdir_line="${gitdir_line%$'\r'}"
    if [[ "$gitdir_line" != gitdir:* ]]; then
      PODMAN_MOUNTS+=("-v" "${host_dir}/.git:${container_dir}/.git:ro,z")
      return 0
    fi

    raw_gitdir="${gitdir_line#gitdir:}"
    raw_gitdir="${raw_gitdir#"${raw_gitdir%%[![:space:]]*}"}"
    raw_gitdir="${raw_gitdir%"${raw_gitdir##*[![:space:]]}"}"

    if [[ "$raw_gitdir" == /* ]]; then
      wt_git_dir=$(realpath -- "$raw_gitdir" 2>/dev/null || true)
    else
      wt_git_dir=$(realpath -- "${host_dir}/${raw_gitdir}" 2>/dev/null || true)
    fi

    if [ -z "$wt_git_dir" ] || [ ! -d "$wt_git_dir" ]; then
      PODMAN_MOUNTS+=("-v" "${host_dir}/.git:${container_dir}/.git:ro,z")
      return 0
    fi

    common_git_dir="$wt_git_dir"
    if [ -f "${wt_git_dir}/commondir" ]; then
      IFS= read -r commondir_line < "${wt_git_dir}/commondir" || true
      commondir_line="${commondir_line%$'\r'}"
      commondir_line="${commondir_line#"${commondir_line%%[![:space:]]*}"}"
      commondir_line="${commondir_line%"${commondir_line##*[![:space:]]}"}"
      if [ -n "$commondir_line" ]; then
        if [[ "$commondir_line" == /* ]]; then
          common_git_dir=$(realpath -- "$commondir_line" 2>/dev/null || echo "$wt_git_dir")
        else
          common_git_dir=$(realpath -- "${wt_git_dir}/${commondir_line}" 2>/dev/null || echo "$wt_git_dir")
        fi
      fi
    fi

    if [[ "$raw_gitdir" == /* ]]; then
      PODMAN_MOUNTS+=("-v" "${host_dir}/.git:${container_dir}/.git:ro,z")
    else
      local safe_name="${host_dir#/}"
      safe_name="${safe_name//\//_}"
      local rewritten_gitfile="${SCRIPT_DIR}/state/GITDIR_${safe_name}"
      printf 'gitdir: %s\n' "$wt_git_dir" > "$rewritten_gitfile"
      PODMAN_MOUNTS+=("-v" "${rewritten_gitfile}:${container_dir}/.git:ro,z")
    fi

    if [ -d "$common_git_dir" ]; then
      if [[ "$common_git_dir" == "${host_dir}/"* ]]; then
        local rel_common="${common_git_dir#"${host_dir}/"}"
        PODMAN_MOUNTS+=("-v" "${common_git_dir}:${container_dir}/${rel_common}:ro,z")
      fi
      mount_git_dir_once "$common_git_dir"
    fi

    if [ "$wt_git_dir" != "$common_git_dir" ] && [[ "$wt_git_dir" != "${common_git_dir}/"* ]]; then
      if [[ "$wt_git_dir" == "${host_dir}/"* ]]; then
        local rel_wt="${wt_git_dir#"${host_dir}/"}"
        PODMAN_MOUNTS+=("-v" "${wt_git_dir}:${container_dir}/${rel_wt}:ro,z")
      fi
      mount_git_dir_once "$wt_git_dir"
    fi
  fi
}

# always mount the workspace directory to /workspace
PODMAN_MOUNTS+=("-v" "${WORKSPACE_DIR}:/workspace:${WORKSPACE_MODE},z")

# mount .git (and worktree git history if applicable) as ro always
mount_git_ro "${WORKSPACE_DIR}" "/workspace"

MOUNTED_TARGETS=("/workspace")
EXTRA_MOUNT_DESC=()
WRITABLE_PATHS=()
if [ "$WORKSPACE_MODE" = "rw" ]; then
  WRITABLE_PATHS+=("\`/workspace\`")
fi
WRITABLE_PATHS+=("\`/tmp\`")

for spec in "${EXTRA_MOUNT_SPECS[@]}"; do
  MOUNT_MODE="$WORKSPACE_MODE"
  if [[ "$spec" == *:ro ]]; then
    MOUNT_MODE="ro"
    spec="${spec%:ro}"
  elif [[ "$spec" == *:rw ]]; then
    MOUNT_MODE="rw"
    spec="${spec%:rw}"
  fi

  if [[ "$spec" == *:* ]]; then
    HOST_DIR="${spec%%:*}"
    CUSTOM_TARGET="${spec#*:}"
  else
    HOST_DIR="$spec"
    CUSTOM_TARGET=""
  fi

  if [ -z "$HOST_DIR" ] || [ ! -d "$HOST_DIR" ]; then
    echo "Error: mount directory does not exist: ${HOST_DIR}" >&2
    exit 1
  fi

  HOST_DIR=$(realpath -- "$HOST_DIR")

  if [ -n "$CUSTOM_TARGET" ]; then
    if [[ "$CUSTOM_TARGET" == /* ]]; then
      CONTAINER_DIR="$CUSTOM_TARGET"
    else
      CONTAINER_DIR="/mnt/${CUSTOM_TARGET}"
    fi
  else
    CONTAINER_DIR="/mnt/$(basename -- "$HOST_DIR")"
  fi
  CONTAINER_DIR="${CONTAINER_DIR%/}"

  for existing in "${MOUNTED_TARGETS[@]}"; do
    if [ "$existing" = "$CONTAINER_DIR" ]; then
      echo "Error: duplicate mount target '${CONTAINER_DIR}'. Specify a custom name with -m <path>:<name>[:ro|rw]" >&2
      exit 1
    fi
  done
  MOUNTED_TARGETS+=("$CONTAINER_DIR")

  echo "mounting ${HOST_DIR} to ${CONTAINER_DIR} (${MOUNT_MODE})"
  PODMAN_MOUNTS+=("-v" "${HOST_DIR}:${CONTAINER_DIR}:${MOUNT_MODE},z")

  mount_git_ro "${HOST_DIR}" "${CONTAINER_DIR}"

  EXTRA_MOUNT_DESC+=("\`${CONTAINER_DIR}\` (${MOUNT_MODE})")
  if [ "$MOUNT_MODE" = "rw" ]; then
    WRITABLE_PATHS+=("\`${CONTAINER_DIR}\`")
  fi
done

if [ ${#EXTRA_MOUNT_SPECS[@]} -gt 0 ]; then
  ACTIVE_RULES="${SCRIPT_DIR}/state/RULES_DYNAMIC.md"
  WRITABLE_LIST=$(printf '%s, ' "${WRITABLE_PATHS[@]}")
  WRITABLE_LIST="${WRITABLE_LIST%, }"
  MOUNT_LIST=$(printf '%s, ' "${EXTRA_MOUNT_DESC[@]}")
  MOUNT_LIST="${MOUNT_LIST%, }"
  cat << EOF > "$ACTIVE_RULES"
# SYSTEM RULES
- Environment: You are running inside an isolated Podman container.
- Write access: ${WRITABLE_LIST} ONLY. All other paths are READ-ONLY.
- Additional mounted directories: ${MOUNT_LIST}.
- CRITICAL: \`.git\` is set to READ-ONLY by the OS. Do not attempt commits, pushes, or writes. Only use read commands.
EOF
elif [ "$WORKSPACE_MODE" = "rw" ]; then
  ACTIVE_RULES="$RULES_RW"
else
  ACTIVE_RULES="$RULES_RO"
fi

PODMAN_MOUNTS+=("-v" "${ACTIVE_RULES}:/tmp/RULES.md:ro,z")

AGENT_FLAGS=("-e" "AGENT=${AGENT}")
if [ "$AGENT" = "claude" ]; then
  PODMAN_MOUNTS+=("-v" "${ACTIVE_RULES}:/etc/claude-code/CLAUDE.md:ro,z")
  CLAUDE_DYNAMIC_SETTINGS="${SCRIPT_DIR}/state/CLAUDE_MANAGED_SETTINGS.json"
  JSON_DIRS="\"/mnt\", \"/tmp\""
  for dir in "${MOUNTED_TARGETS[@]}"; do
    if [ "$dir" != "/workspace" ]; then
      escaped_dir="${dir//\\/\\\\}"
      escaped_dir="${escaped_dir//\"/\\\"}"
      JSON_DIRS="${JSON_DIRS}, \"${escaped_dir}\""
    fi
  done
  cat << EOF > "$CLAUDE_DYNAMIC_SETTINGS"
{
  "managedSourcesBehavior": "merge",
  "permissions": {
    "additionalDirectories": [${JSON_DIRS}],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)"
    ]
  }
}
EOF
  PODMAN_MOUNTS+=("-v" "${CLAUDE_DYNAMIC_SETTINGS}:/etc/claude-code/managed-settings.json:ro,z")
  AGENT_FLAGS+=(
    "-e" "CLAUDE_CONFIG_DIR=/home/opencode-user/.claude"
    "-e" "XDG_CONFIG_HOME=/home/opencode-user/.claude/xdg_config"
    "-e" "XDG_STATE_HOME=/home/opencode-user/.claude/xdg_state"
    "-e" "DISABLE_AUTOUPDATER=1"
    "-e" "DISABLE_UPDATES=1"
    "-v" "${SCRIPT_DIR}/claude_state:/home/opencode-user/.claude:Z,U"
    "-v" "${SCRIPT_DIR}/claude_state/xdg_config:/home/opencode-user/.config:Z,U"
  )
else
  AGENT_FLAGS+=(
    "-e" "XDG_STATE_HOME=/home/opencode-user/.local/share/opencode/xdg_state"
    "-e" "OPENCODE_DISABLE_AUTOUPDATE=1"
    "-e" "OPENCODE_CONFIG_CONTENT={\"instructions\": [\"/tmp/RULES.md\"]}"
    "-v" "${SCRIPT_DIR}/state:/home/opencode-user/.local/share/opencode:Z,U"
    "-v" "${SCRIPT_DIR}/opencode.jsonc:/home/opencode-user/.config/opencode/opencode.jsonc:ro,z"
    "-v" "${SCRIPT_DIR}/opencode_service.json:/home/opencode-user/.config/opencode/service.json:ro,z"
    "-v" "${SCRIPT_DIR}/opencode_cli.json:/home/opencode-user/.config/opencode/cli.json:ro,z"
    "-v" "${SCRIPT_DIR}/opencode.gitignore:/home/opencode-user/.config/opencode/.gitignore:ro,z"
  )
fi

PODMAN_DNS=()
if [ "$ALLOW_INTERNAL_IPS" != "1" ]; then
  PODMAN_DNS+=("--dns=1.1.1.1" "--dns=8.8.8.8")
fi

if [ "$SHOW_WRAPPER_HELP" = "1" ]; then
  cat << 'EOF'
SANDBOX WRAPPER FLAGS
  -rw                              Mount current directory (/workspace) as read-write (default: ro)
  -lan                             Allow access to internal/private network IPs
  -m <dir>[:<name>][:ro|rw]        Mount an additional host directory to /mnt/<name> (or /<path> if absolute)
  -m=<dir>[:<name>][:ro|rw]        Same as -m (inherits workspace ro/rw mode unless :ro or :rw is specified)
  -claude, --claude                Run the Claude Code CLI agent (default when invoked as 'claude')
  -opencode, --opencode            Run the OpenCode CLI agent (default when invoked as 'opencode')

EOF
fi

exec podman run -it --rm \
  --name "${AGENT}-sandbox-$$" \
  --cap-drop=ALL \
  --cap-add=CAP_NET_ADMIN \
  --cap-add=CAP_SETPCAP \
  "${PODMAN_DNS[@]}" \
  --userns=keep-id:uid=1000,gid=1000 \
  --read-only \
  -v /tmp \
  --pids-limit=200 \
  --memory=4g \
  --cpus=4 \
  --sysctl net.ipv6.conf.all.disable_ipv6=1 \
  --sysctl net.ipv6.conf.default.disable_ipv6=1 \
  -e XDG_CACHE_HOME=/tmp/cache \
  -e ALLOW_INTERNAL_IPS="$ALLOW_INTERNAL_IPS" \
  "${AGENT_FLAGS[@]}" \
  "${PODMAN_MOUNTS[@]}" \
  --env-file="${SCRIPT_DIR}/.env" \
  "${AGENT}-sandbox" "${ARGS[@]}"
