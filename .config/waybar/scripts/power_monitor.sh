#!/bin/bash

# --- CONFIGURATION ---
POWER_CPU_PATH="/sys/class/powercap/intel-rapl:0/energy_uj"
LOG_FILE="/tmp/power_history.log"
TEMP_FILE="/tmp/waybar_temps"
MAX_LINES=900
BATTERY_PATH="/sys/class/power_supply/BAT0"

# Find AC Adapter (Mains)
AC_PATH=$(grep -l "Mains" /sys/class/power_supply/*/type 2>/dev/null | head -n 1 | xargs dirname 2>/dev/null)

# State Variables for Notifications
LOW_BAT_NOTIFIED_LEVEL=100
LAST_BAT_STATUS=""
LAST_AC_ONLINE=""

REC_STATE=false

# --- DYNAMIC SENSOR FINDING ---
# Find the thermal zone file where the type is "x86_pkg_temp" (CPU)
TEMP_CPU_PATH=$(grep -l "x86_pkg_temp" /sys/class/thermal/thermal_zone*/type | sed 's/type/temp/')

# Permission check
if [ ! -r "$POWER_CPU_PATH" ]; then
    echo "Err:Perms"
    exit 1
fi

# Setup files
touch "$LOG_FILE"
touch "$TEMP_FILE"

LAST_VAL=$(cat "$POWER_CPU_PATH")
CLEANUP_COUNTER=0

while true; do
    sleep 2

    # --- POWER CALC ---
    CURR_VAL=$(cat "$POWER_CPU_PATH")
    DIFF=$((CURR_VAL - LAST_VAL))
    CPU_W=$(echo "$DIFF" | awk '{printf "%04.1f", $1 / 2000000}')
    TOTAL_W=$(sensors | awk '/power1:/ {printf "%04.1f", $2}')

    # --- TEMP CALC ---
    # Read CPU file, divide by 1000 to get Celsius
    if [ -r "$TEMP_CPU_PATH" ]; then
        RAW_CPU=$(cat "$TEMP_CPU_PATH")
        CPU_T=$((RAW_CPU / 1000))
    else
        CPU_T="?"
    fi

    # --- BATTERY & AC CHECK ---
    if [ -d "$BATTERY_PATH" ]; then
        BAT_STATUS=$(cat "$BATTERY_PATH/status")
        BAT_CAPACITY=$(cat "$BATTERY_PATH/capacity")

        # Initialize LAST_BAT_STATUS on first run
        if [[ -z "$LAST_BAT_STATUS" ]]; then
            LAST_BAT_STATUS="$BAT_STATUS"
        fi

        # Check AC Adapter State if available
        if [ -n "$AC_PATH" ] && [ -r "$AC_PATH/online" ]; then
            AC_ONLINE=$(cat "$AC_PATH/online")
            
            if [[ -z "$LAST_AC_ONLINE" ]]; then
                LAST_AC_ONLINE="$AC_ONLINE"
            fi

            # 1. Charger Connected
            if [[ "$AC_ONLINE" == "1" && "$LAST_AC_ONLINE" == "0" ]]; then
                notify-send -u normal " Charger Connected" "Battery at ${BAT_CAPACITY}%" -i battery-charging-40 -t 5000
            fi

            # 2. Charger Disconnected
            if [[ "$AC_ONLINE" == "0" && "$LAST_AC_ONLINE" == "1" ]]; then
                notify-send -u normal " Charger Disconnected" "Battery at ${BAT_CAPACITY}%" -i battery-full -t 5000
            fi
            
            LAST_AC_ONLINE="$AC_ONLINE"
        fi

        # 3. Battery Limit Reached
        # Trigger: Status stops being "Charging" (becomes "Not charging", "Full", or "Unknown") AND Charger is connected.
        if [[ "$LAST_BAT_STATUS" == "Charging" && "$BAT_STATUS" != "Charging" && "$BAT_STATUS" != "Discharging" && "$AC_ONLINE" == "1" ]]; then
             notify-send -u normal " Battery Limit Reached" "Charging stopped at ${BAT_CAPACITY}%" -i battery-full-charged -t 5000
        fi

        # Reset low battery flags when charging (or rather, when status indicates charging or full)
        if [[ "$BAT_STATUS" == "Charging" || "$BAT_STATUS" == "Full" ]]; then
            LOW_BAT_NOTIFIED_LEVEL=100
        fi

        # 4. Low Battery Notifications (Discharging)
        if [[ "$BAT_STATUS" == "Discharging" ]]; then
            if [[ "$BAT_CAPACITY" -le 1 && "$LOW_BAT_NOTIFIED_LEVEL" -gt 1 ]]; then
                 notify-send -u critical " Critical Battery!" "Battery is at 1%. Shutting down imminent." -i battery-empty -t 0
                 LOW_BAT_NOTIFIED_LEVEL=1
            elif [[ "$BAT_CAPACITY" -le 2 && "$LOW_BAT_NOTIFIED_LEVEL" -gt 2 ]]; then
                 notify-send -u critical " Critical Battery!" "Battery is at 2%" -i battery-empty -t 0
                 LOW_BAT_NOTIFIED_LEVEL=2
            elif [[ "$BAT_CAPACITY" -le 3 && "$LOW_BAT_NOTIFIED_LEVEL" -gt 3 ]]; then
                 notify-send -u critical " Critical Battery!" "Battery is at 3%" -i battery-empty -t 0
                 LOW_BAT_NOTIFIED_LEVEL=3
            elif [[ "$BAT_CAPACITY" -le 5 && "$LOW_BAT_NOTIFIED_LEVEL" -gt 5 ]]; then
                 notify-send -u critical " Low Battery" "Battery is at 5%" -i battery-caution -t 0
                 LOW_BAT_NOTIFIED_LEVEL=5
            elif [[ "$BAT_CAPACITY" -le 10 && "$LOW_BAT_NOTIFIED_LEVEL" -gt 10 ]]; then
                 notify-send -u critical " Low Battery" "Battery is at 10%" -i battery-caution -t 30000
                 LOW_BAT_NOTIFIED_LEVEL=10
            fi
        fi

        LAST_BAT_STATUS="$BAT_STATUS"
    fi

    # --- SCREEN RECORDING MONITOR ---
    # Check if recording is active
    if pgrep -f "gpu-screen-recorder" >/dev/null || pgrep -f "WebcamOverlay" >/dev/null; then
        CURRENT_REC_STATE=true
    else
        CURRENT_REC_STATE=false
    fi

    # If state changed, signal Waybar to update the indicator module
    if [ "$REC_STATE" != "$CURRENT_REC_STATE" ]; then
        pkill -RTMIN+8 waybar
        REC_STATE=$CURRENT_REC_STATE
    fi

    # --- OUTPUTS ---

    # 1. Main Output (Power) -> "04.5/12.2 W"
    echo "${CPU_W}/${TOTAL_W}W"

    # 2. Side Channel (Temp) -> "43°C"
    echo "${CPU_T}°C" > "$TEMP_FILE"

    # 3. Logging -> Time | Power | Temp: 43C
    TIMESTAMP=$(date '+%H:%M:%S')
    echo "$TIMESTAMP | Power: ${CPU_W}/${TOTAL_W}W | Temp: ${CPU_T}C" >> "$LOG_FILE"

    # --- CLEANUP ---
    ((CLEANUP_COUNTER++))
    if [ "$CLEANUP_COUNTER" -ge 10 ]; then
        tail -n "$MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        CLEANUP_COUNTER=0
    fi

    LAST_VAL=$CURR_VAL
done
