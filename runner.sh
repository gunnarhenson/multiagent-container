#!/usr/bin/env bash

WORKSPACE_MODE="ro"
ARGS=()
EXTRA_MOUNT_SPECS=()

ALLOW_INTERNAL_IPS="0"
SHOW_WRAPPER_HELP="0"
while [ $# -gt 0 ]; do
  case "$1" in
    -rw)
      WORKSPACE_MODE="rw"
      echo "starting opencode in rw mode"
      shift
      ;;
    -lan)
      ALLOW_INTERNAL_IPS="1"
      echo "starting opencode with internal network access"
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

SCRIPT_DIR=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")

if [ ! -f "${SCRIPT_DIR}/opencode.jsonc" ]; then
    touch "${SCRIPT_DIR}/opencode.jsonc"
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
# always mount the current directory to /workspace
PODMAN_MOUNTS+=("-v" "$(pwd):/workspace:${WORKSPACE_MODE},z")

# mount .git as ro always
if [ -e "$(pwd)/.git" ]; then
  PODMAN_MOUNTS+=("-v" "$(pwd)/.git:/workspace/.git:ro,z")
fi

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

  if [ -e "${HOST_DIR}/.git" ]; then
    PODMAN_MOUNTS+=("-v" "${HOST_DIR}/.git:${CONTAINER_DIR}/.git:ro,z")
  fi

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

EOF
fi

exec podman run -it --rm \
  --name "opencode-sandbox-$$" \
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
  -e XDG_STATE_HOME=/home/opencode-user/.local/share/opencode/xdg_state \
  -e XDG_CACHE_HOME=/tmp/cache \
  -e ALLOW_INTERNAL_IPS="$ALLOW_INTERNAL_IPS" \
  -e OPENCODE_DISABLE_AUTOUPDATE=1 \
  -e OPENCODE_CONFIG_CONTENT='{"instructions": ["/tmp/RULES.md"]}' \
  -v "${SCRIPT_DIR}/state:/home/opencode-user/.local/share/opencode:Z,U" \
  -v "${SCRIPT_DIR}/opencode.jsonc:/home/opencode-user/.config/opencode/opencode.jsonc:ro,z" \
  -v "${SCRIPT_DIR}/opencode_service.json:/home/opencode-user/.config/opencode/service.json:ro,z" \
  -v "${SCRIPT_DIR}/opencode_cli.json:/home/opencode-user/.config/opencode/cli.json:ro,z" \
  -v "${SCRIPT_DIR}/opencode.gitignore:/home/opencode-user/.config/opencode/.gitignore:ro,z" \
  "${PODMAN_MOUNTS[@]}" \
  --env-file="${SCRIPT_DIR}/.env" \
  opencode-sandbox "${ARGS[@]}"
