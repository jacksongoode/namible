#!/bin/sh
set -uo pipefail

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOGFILE="/mnt/us/apps/namible/namible.log"
PYTHON_LOG="/mnt/us/apps/namible/python_debug.log"
PIDFILE="/var/tmp/namible.pid"

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

stop_framework() {
    # First, stop all non-essential supporting services.
    log "Stopping supporting services..."
    # for service in otaupd phd tmd x todo mcsd archive dynconfig dpmd appmgrd stackdumpd; do
    #     stop "$service" 2>/dev/null
    # done
    log "Stopping Kindle framework"
    lipc-set-prop com.lab126.powerd preventScreenSaver 1
    trap "" SIGTERM
    stop lab126_gui
    sleep 1.5
    trap - SIGTERM
}

start_framework() {
    log "Restoring Kindle framework"
    start lab126_gui
    lipc-set-prop com.lab126.powerd preventScreenSaver 0
}

cleanup() {
    log "Cleanup: restoring device state"
    start_framework
    lipc-set-prop com.lab126.cmd wirelessEnable 0
    rm -f "$PIDFILE"
    exit 0
}

cd "$(dirname "$0")" || exit 1

if [ -f "$PIDFILE" ] && ps -p "$(cat "$PIDFILE")" > /dev/null; then
    log "Already running. Exiting."
    exit 1
fi
echo "$$" > "$PIDFILE"
log "Namible started (PID: $$)"

chmod +x ./yt-dlp ./ffmpeg ./fbink

log "Turning off frontlight"
lipc-set-prop com.lab126.powerd flIntensity 0 || true
echo 0 > /sys/devices/platform/11007000.i2c/i2c-0/0-0034/backlight/fp9966-bl0/brightness 2>/dev/null || true
echo 0 > /sys/devices/platform/11007000.i2c/i2c-0/0-0034/backlight/fp9966-bl1/brightness 2>/dev/null || true

log "Reading configuration"
CONFIG=$(python3 ./get_namib.py get-config 2>> "$LOGFILE")
if [ $? -ne 0 ]; then
    log "FATAL: Could not read config.json"
    ./fbink -c -h "Fatal: Bad config.json"
    exit 1
fi
VIDEO_ID=$(echo "$CONFIG" | cut -d' ' -f1)
SLEEP_SECONDS=$(echo "$CONFIG" | cut -d' ' -f2)
log "Config: VideoID=$VIDEO_ID, Sleep=$SLEEP_SECONDS"

stop_framework
if [ -f "photo.png" ]; then
    log "Displaying initial photo"
    ./fbink -c -f -g "file=photo.png"
fi

log "Setting CPU to powersave mode"
echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

trap cleanup INT TERM EXIT
log "Entering main loop"

REFRESH_COUNT=0
while true; do
    log "Waking up, enabling Wi-Fi"
    lipc-set-prop com.lab126.cmd wirelessEnable 1

    TRIES=0
    while ! lipc-get-prop com.lab126.wifid cmState | grep -q "CONNECTED" && [ $TRIES -lt 45 ]; do
        sleep 1
        TRIES=$((TRIES + 1))
    done

    if lipc-get-prop com.lab126.wifid cmState | grep -q "CONNECTED" && ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        log "Network is up. Fetching frame"
        if python3 ./get_namib.py get-frame "$VIDEO_ID" > "$PYTHON_LOG" 2>&1; then
            log "Fetch successful. Refreshing display"
            if [ $((REFRESH_COUNT % 10)) -eq 0 ]; then
                ./fbink -c -f -g "file=photo.png"
            else
                ./fbink -g "file=photo.png"
            fi
            REFRESH_COUNT=$((REFRESH_COUNT + 1))
        else
            log "ERROR: Python script failed. See python_debug.log"
            tail -n 5 "$PYTHON_LOG" >> "$LOGFILE"
        fi
    else
        log "Network not ready. Skipping update"
    fi

    log "Disabling Wi-Fi and sleeping for $SLEEP_SECONDS seconds"
    lipc-set-prop com.lab126.cmd wirelessEnable 0
    sleep 2
    rtcwake -d /dev/rtc1 -m mem -s "$SLEEP_SECONDS"
done
