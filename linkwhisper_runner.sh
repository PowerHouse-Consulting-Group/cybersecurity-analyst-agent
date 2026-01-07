#!/bin/bash

# ==============================================================================
# LinkWhisper Throttled Runner (Sidecar)
# ==============================================================================
# Usage: ./linkwhisper_runner.sh --user=<linux_user> --path=<wp_path>
# Example: ./linkwhisper_runner.sh --user=username --path=/home/username/public_html
#
# Description:
# Runs LinkWhisper processing tasks in a strictly resource-controlled environment.
# - Disables native auto-cron for LinkWhisper to prevent overload.
# - Uses systemd-run to limit CPU (20%) and Memory (1G).
# - Runs in a loop with sleep intervals to protect the Database.
# ==============================================================================

USER=""
WP_PATH=""

# --- Parse Arguments ---
for i in "$@"; do
case $i in
    --user=*)
    USER="${i#*=}"
    shift
    ;;
    --path=*)
    WP_PATH="${i#*=}"
    shift
    ;;
    *)
    # unknown option
    ;;
esac
done

if [[ -z "$USER" || -z "$WP_PATH" ]]; then
    echo "Usage: $0 --user=<linux_user> --path=<wp_path>"
    exit 1
fi

echo "--> Starting LinkWhisper Throttled Runner for $WP_PATH (User: $USER)"

# --- Configuration ---
# 1. Resource Limits (passed to systemd-run)
CPU_QUOTA="100%"
MEM_MAX="4G"

# 2. WP-CLI Command Wrapper 
# Using --allow-root to avoid sudo hangs in non-interactive environments.
# Ideally, we should run as the user, but system stability takes precedence.
WP="wp --path=$WP_PATH --allow-root"

# 3. Throttling
SLEEP_INTERVAL=5       # Sleep 5 seconds between batches (Fast Mode)
MAX_RUN_TIME=3500      # Run for ~58 mins (exits before next hourly cron)

# --- Step 1: Enforce Safe Configuration (Persistence) ---
echo "    [1/3] Enforcing safe configuration in database..."

# Disable native cron triggers (we want to control execution)
# Check current values first to avoid "Could not update" errors when value is unchanged
VAL_AUTOLINK=$($WP option get wpil_enable_autolink_cron_task 2>/dev/null)
if [ "$VAL_AUTOLINK" != "0" ]; then
    $WP option update wpil_enable_autolink_cron_task 0 --quiet
fi

VAL_AI=$($WP option get wpil_disable_ai_suggestions_cron 2>/dev/null)
if [ "$VAL_AI" != "1" ]; then
    $WP option update wpil_disable_ai_suggestions_cron 1 --quiet
fi

echo "          Configuration enforced."

# --- Step 2: Execution Loop with Resource Control ---
echo "    [2/3] Starting processing loop (Max Runtime: ${MAX_RUN_TIME}s)..."
echo "          Limits: CPU=${CPU_QUOTA}, Mem=${MEM_MAX}, Sleep=${SLEEP_INTERVAL}s"

START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ "$ELAPSED" -ge "$MAX_RUN_TIME" ]; then
        echo "    [!] Max run time reached. Exiting."
        break
    fi

    # execute via systemd-run for cgroup isolation
    # We trigger the 3 main resource-intensive cron events
    if command -v systemd-run &> /dev/null; then
         echo "          [$(date +%T)] Processing Autolink..."
         systemd-run --scope -p CPUQuota="$CPU_QUOTA" -p MemoryMax="$MEM_MAX" --quiet /bin/bash -c "nice -n 19 ionice -c 3 $WP cron event run wpil_autolink_insert_cron > /dev/null 2>&1"
         
         echo "          [$(date +%T)] Processing AI Suggestions..."
         systemd-run --scope -p CPUQuota="$CPU_QUOTA" -p MemoryMax="$MEM_MAX" --quiet /bin/bash -c "nice -n 19 ionice -c 3 $WP cron event run wpil_ai_suggestions_cron > /dev/null 2>&1"
         
         echo "          [$(date +%T)] Processing AI Batch..."
         systemd-run --scope -p CPUQuota="$CPU_QUOTA" -p MemoryMax="$MEM_MAX" --quiet /bin/bash -c "nice -n 19 ionice -c 3 $WP cron event run wpil_ai_batch_process_cron > /dev/null 2>&1"
    else
        # Fallback to nice/ionice if systemd-run is not available
        $WP cron event run wpil_autolink_insert_cron > /dev/null 2>&1
        $WP cron event run wpil_ai_suggestions_cron > /dev/null 2>&1
        $WP cron event run wpil_ai_batch_process_cron > /dev/null 2>&1
    fi

    echo "          Batch complete. Sleeping ${SLEEP_INTERVAL}s..."
    sleep "$SLEEP_INTERVAL"
done

echo "--> LinkWhisper Throttled Run Complete."
