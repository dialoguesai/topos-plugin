# Shared helpers for the topos plugin launchers. POSIX sh; sourced, never executed.
#
# GUI-launched hosts (Claude desktop app, Codex desktop, Cursor) start MCP servers
# and hooks with an EMPTY PATH (spike P0.5, 2026-10-15: `launchctl getenv PATH`
# is empty; launchd jobs get /usr/bin:/bin:/usr/sbin:/sbin). Nothing here may
# depend on PATH. The node binary is resolved by the fixed candidate list below
# (CONTRACTS.md §4, the Topos.app order), never by `command -v topos-node`.
#
# Nothing in this file prints a secret, reads ~/.topos/.env, or touches the
# label file.

topos_sane_path() {
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:${HOME:-/}/.local/bin${PATH:+:$PATH}"
    export PATH
}

# Prints the absolute path of the topos-node binary, or returns 1.
# $1 (optional): a path to exclude, so a wrapper never resolves to itself.
topos_resolve_node() {
    _self="${1:-}"
    _home="${HOME:-/}"
    for _c in "${TOPOS_NODE_BIN:-}" \
              "$_home/.local/bin/topos-node" \
              "$_home/.topos/runtime/bin/topos-node" \
              /opt/homebrew/bin/topos-node \
              /usr/local/bin/topos-node; do
        [ -n "$_c" ] || continue
        [ -x "$_c" ] || continue
        [ -d "$_c" ] && continue
        if [ -n "$_self" ] && [ "$_c" -ef "$_self" ]; then
            continue
        fi
        printf '%s\n' "$_c"
        return 0
    done
    return 1
}

# The node's unix socket (topos/uds.py: TOPOS_UDS_PATH or ~/.topos/engine.sock).
topos_socket_path() {
    printf '%s\n' "${TOPOS_UDS_PATH:-${HOME:-/}/.topos/engine.sock}"
}

# Prints a usable python3, or returns 1. Fixed locations first; PATH last.
topos_python() {
    for _p in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 \
              "$(command -v python3 2>/dev/null)"; do
        [ -n "$_p" ] || continue
        [ -x "$_p" ] || continue
        # /usr/bin/python3 on a fresh Mac is a stub that opens the Command Line
        # Tools installer; a real interpreter answers --version at once.
        if "$_p" -I -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
            printf '%s\n' "$_p"
            return 0
        fi
    done
    return 1
}

# Reads `--client NAME` / `--client=NAME` from "$@" and prints the name.
topos_arg_client() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --client) printf '%s\n' "${2:-}"; return 0 ;;
            --client=*) printf '%s\n' "${1#--client=}"; return 0 ;;
        esac
        shift
    done
    printf '%s\n' ""
}
