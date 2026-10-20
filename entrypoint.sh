#!/bin/sh
set -e

if [ "$ALLOW_INTERNAL_IPS" != "1" ]; then
    ip route add blackhole 10.0.0.0/8
    ip route add blackhole 172.16.0.0/12
    ip route add blackhole 192.168.0.0/16
    ip route add blackhole 169.254.0.0/16
fi

mkdir -p /tmp/state /tmp/cache
chown -R 1000:1000 /tmp/state /tmp/cache

export HOME="/home/opencode-user"
export USER="opencode-user"
export LOGNAME="opencode-user"

if [ "$AGENT" = "claude" ]; then
    mkdir -p /home/opencode-user/.claude/xdg_config/anthropic /home/opencode-user/.claude/xdg_state
    chown -R 1000:1000 /home/opencode-user/.claude 2>/dev/null || true
    AGENT_BIN="/opt/claude/bin/claude"
else
    chown -R 1000:1000 /home/opencode-user/.local/share/opencode 2>/dev/null || true
    AGENT_BIN="/opt/opencode/.opencode/bin/opencode"
fi

exec setpriv \
    --inh-caps=-all \
    --bounding-set=-all \
    --no-new-privs \
    -- "$AGENT_BIN" "$@"
