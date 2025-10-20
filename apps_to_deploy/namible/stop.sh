#!/bin/sh

# This script safely stops the Namible viewer.
# It is designed to be launched from KUAL.

PIDFILE="/var/tmp/namible.pid"

if [ -e "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    echo "Found PID file. Stopping Namible (PID: $PID)..."
    # Send the TERM signal, which will be caught by the 'trap' in start.sh
    kill "$PID"
    sleep 2
    ./fbink -c -h "Namible has been stopped."
else
    echo "PID file not found. Is Namible running?"
    ./fbink -c -h "Namible does not appear to be running."
fi
