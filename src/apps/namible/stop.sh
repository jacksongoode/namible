#!/bin/sh

PIDFILE="/var/tmp/namible.pid"
LOGFILE="/mnt/us/apps/namible/namible.log"

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - [STOP] $1" >> "$LOGFILE"
}

log "Stop script initiated."

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    log "Found PID file for process $PID."

    # Check if the process is actually running
    if ps -p "$PID" > /dev/null; then
        log "Process $PID is running. Sending TERM signal for graceful shutdown..."
        # The TERM signal is caught by the trap in start.sh, triggering the cleanup function.
        kill "$PID"
        
        # Wait a moment to see if it shuts down gracefully
        sleep 3

        # If it's still running, it may be stuck. Force kill it.
        if ps -p "$PID" > /dev/null; then
            log "Process did not stop gracefully. Sending KILL signal."
            kill -9 "$PID"
        else
            log "Process stopped gracefully."
        fi
    else
        log "Process $PID was not running, but a stale PID file existed. Cleaning up file."
    fi
    
    # Remove the PID file
    rm -f "$PIDFILE"
else
    log "PID file not found. Namible does not appear to be running."
fi

# Failsafe Cleanup
# This part runs regardless of whether the PID file was found. It ensures
# the Kindle is always restored to a usable state, even if the main script
# crashed without cleaning up properly.
log "Performing failsafe cleanup to restore Kindle state..."
start lab126_gui
lipc-set-prop com.lab126.powerd preventScreenSaver 0
log "Failsafe cleanup complete. Kindle framework restored."

log "Stop script finished."
exit 0