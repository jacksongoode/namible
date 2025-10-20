#!/bin/sh

LOGFILE="/mnt/us/apps/namible/namible.log"
PYTHON_LOG="/mnt/us/apps/namible/python_debug.log"
FBROTATE="/sys/devices/platform/14000000.hwtcon_v2/graphics/fb0/rotate"
PIDFILE="/var/tmp/namible.pid"
FRAMEWORK_STOPPED=0

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

get_config() {
    log "Reading configuration..."
    CONFIG=$(python3 ./get_youtube_frame.py get-config 2>> "$LOGFILE")
    if [ $? -ne 0 ]; then
        log "FATAL: Could not read config.json."
        ./fbink -c -h "Fatal Error: Invalid config.json"
        exit 1
    fi
    VIDEO_ID=$(echo "$CONFIG" | cut -d' ' -f1)
    SLEEP_SECONDS=$(echo "$CONFIG" | cut -d' ' -f2)
    WIFI_SSID=$(echo "$CONFIG" | cut -d' ' -f3)
    WIFI_PSK=$(echo "$CONFIG" | cut -d' ' -f4)
    ENABLE_WIFI=$(echo "$CONFIG" | cut -d' ' -f5)
    SAFE_MODE=$(echo "$CONFIG" | cut -d' ' -f6)
}

manage_framework() {
    if [ "$SAFE_MODE" = "True" ]; then
        log "Safe mode enabled, skipping framework management."
        return
    fi

    if [ "$1" = "stop" ]; then
        log "Stopping Kindle framework..."
        FRAMEWORK_STOPPED=1
        for service in lab126_gui otaupd phd tmd x todo mcsd archive dynconfig dpmd appmgrd stackdumpd; do
            stop "$service" 2>/dev/null
        done
        lipc-set-prop com.lab126.powerd preventScreenSaver 1
    elif [ "$1" = "start" ]; then
        log "Starting Kindle framework..."
        if [ "$FRAMEWORK_STOPPED" -eq 1 ]; then
            start lab126_gui
        fi
    fi
}

connect_wifi() {
    log "Connecting to Wi-Fi..."
    lipc-set-prop com.lab126.cmd wirelessEnable 1
    NET_ID=$(wpa_cli add_network | sed -n '2p')
    wpa_cli <<EOF > /dev/null
set_network $NET_ID ssid "$WIFI_SSID"
set_network $NET_ID psk "$WIFI_PSK"
set_network $NET_ID key_mgmt WPA-PSK
select_network $NET_ID
enable_network $NET_ID
EOF
    TRIES=0
    while ! lipc-get-prop com.lab126.wifid cmState | grep -q "CONNECTED" && [ $TRIES -lt 45 ]; do
        sleep 1; TRIES=$((TRIES + 1))
    done

    if ! lipc-get-prop com.lab126.wifid cmState | grep -q "CONNECTED"; then
        log "Error: Wi-Fi connection failed."
        ./fbink -c -h "Error: Wi-Fi failed"
        return 1
    fi
    log "Wi-Fi connected."
    return 0
}

update_image() {
    log "Fetching new frame..."
    python3 ./get_youtube_frame.py get-frame "$VIDEO_ID" > "$PYTHON_LOG" 2>&1
    if [ $? -eq 0 ]; then
        log "Frame captured. Displaying pre-rotated image."
        ./fbink -c -g "file=photo.png"
    else
        log "ERROR: Python script failed. See $PYTHON_LOG for details."
        ./fbink -c -h "Python script FAILED."
    fi
}

go_to_sleep() {
    if [ "$ENABLE_WIFI" = "True" ]; then
        log "Debug sleep enabled. Waiting 30 seconds."
        sleep 30
        return 0
    fi

    log "Disabling Wi-Fi and sleeping for $SLEEP_SECONDS seconds."
    lipc-set-prop com.lab126.cmd wirelessEnable 0
    sleep 2

    START_TIME=$(date +%s)
    rtcwake -d /dev/rtc1 -m mem -s "$SLEEP_SECONDS"
    END_TIME=$(date +%s)

    ELAPSED=$((END_TIME - START_TIME))
    if [ $ELAPSED -lt $((SLEEP_SECONDS - 5)) ]; then
        log "Woke up early by power button after $ELAPSED seconds. Exiting."
        return 1 # Signal to exit main loop
    fi
    return 0
}

cleanup() {
    log "Caught exit signal. Cleaning up..."
    if [ -e "$FBROTATE" ]; then echo 0 > "$FBROTATE"; fi
    manage_framework "start"
    lipc-set-prop com.lab126.cmd wirelessEnable 0
    rm -f "$PIDFILE"
    log "Cleanup complete."
    exit 0
}

cd "$(dirname "$0")"
chmod +x ./yt-dlp ./ffmpeg ./fbink

# Disable auto-brightness and turn off the frontlight
log "Disabling auto-brightness and turning off frontlight..."
lipc-set-prop com.lab126.powerd fflMode 0
BRIGHTNESS_FILE_0="/sys/devices/platform/11007000.i2c/i2c-0/0-0034/backlight/fp9966-bl0/brightness"
BRIGHTNESS_FILE_1="/sys/devices/platform/11007000.i2c/i2c-0/0-0034/backlight/fp9966-bl1/brightness"
if [ -e "$BRIGHTNESS_FILE_0" ]; then echo 0 > "$BRIGHTNESS_FILE_0"; fi
if [ -e "$BRIGHTNESS_FILE_1" ]; then echo 0 > "$BRIGHTNESS_FILE_1"; fi

trap cleanup INT TERM EXIT

echo "$$" > "$PIDFILE"
log "--- Namible Started ---"

get_config
manage_framework "stop"

while true; do
    log "--- Starting Loop Cycle ---"
    if connect_wifi; then
        update_image
    fi

    if ! go_to_sleep; then
        break # Exit loop if go_to_sleep signals a manual stop
    fi
done

cleanup
