#!/bin/bash
# Enforces GNOME screen lock policy via dconf: idle timeout + lock-on-resume.
# Writes three managed files (profile, config, locks) and only calls
# dconf update when at least one file actually changed, making it safe to
# run repeatedly without side effects.

# -e: exit on error  -u: error on undefined var  -o pipefail: catch pipe failures
set -euo pipefail

# Only value that needs changing to adjust the idle timeout policy (seconds)
IDLE_DELAY=360

readonly PROFILE=/etc/dconf/profile/user
readonly CONFIG=/etc/dconf/db/local.d/00-screensaver
readonly LOCKS=/etc/dconf/db/local.d/locks/screensaver

# Logs to stdout (captured by Intune) and syslog (visible via journalctl on device)
log() {
    local level="$1" msg="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $msg"
    logger -t screen_lock_idle "[$level] $msg"
}

[[ $EUID -eq 0 ]] || { log ERROR "Must run as root"; exit 1; }

changed=false

# Compares file content and only writes if different, then sets changed=true
# so dconf update runs once at the end rather than per file.
# '|| true' on cat prevents set -e from exiting when the file doesn't yet exist.
write_if_changed() {
    local file="$1" content="$2"
    local current
    current=$(cat "$file" 2>/dev/null || true)
    if [[ "$current" != "$content" ]]; then
        mkdir -p "$(dirname "$file")"
        printf '%s\n' "$content" > "$file"
        log INFO "Updated $file"
        changed=true
    fi
}

# Tells dconf to load managed settings from the system-db:local database
write_if_changed "$PROFILE" \
"user-db:user
system-db:local"

# lock-enabled=true is required to actually lock the screen on resume,
# not just blank it — idle-delay alone is insufficient on some GNOME versions
write_if_changed "$CONFIG" \
"[org/gnome/desktop/session]
idle-delay=uint32 ${IDLE_DELAY}

[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=uint32 0"

# Prevents users from overriding the above settings in their own dconf profile
write_if_changed "$LOCKS" \
"/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/lock-delay"

if [[ $changed == true ]]; then
    dconf update
    log INFO "dconf database updated (idle-delay=${IDLE_DELAY}s, lock enforced)"
else
    log INFO "Configuration already up to date, no changes applied"
fi
