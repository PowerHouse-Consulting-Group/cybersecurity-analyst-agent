#!/bin/bash

# This script checks for new audit events and emails a report if suspicious activity is found.

# --- Configuration ---
EMAIL_TO="vasilis@powerhouseconsulting.group"
# The keys we set in our audit rules file.
AUDIT_KEYS_TO_CHECK="wp_config_change vjinno5_uploads_watch tmatravel_uploads_watch crond_dropper_watch postfix_permission_change apache_config_change"
# --- End Configuration ---

FINAL_REPORT_FILE=$(mktemp /tmp/audit_report.XXXXXX)
trap 'rm -f "$FINAL_REPORT_FILE"; exit $?' INT TERM EXIT

HAS_EVENTS=0

for key in $AUDIT_KEYS_TO_CHECK; do
    CHECKPOINT_FILE="/root/.audit_checkpoint_${key}"

    # Get all new events for this key
    NEW_EVENTS=$(sudo ausearch -k "$key" --checkpoint "$CHECKPOINT_FILE" -i)

    # If this is an "uploads_watch" key, filter for .php files only
    if [[ "$key" == *"_uploads_watch"* ]]; then
        # This grep will make NEW_EVENTS empty if no .php files are found
        NEW_EVENTS=$(echo "$NEW_EVENTS" | grep -E "name=.*\.php")
    fi

    # If after filtering, we still have events, add them to the report.
    if [ -n "$NEW_EVENTS" ]; then
        HAS_EVENTS=1
        echo -e "### Suspicious Activity Detected for Key: $key ###\n" >> "$FINAL_REPORT_FILE"
        echo -e "$NEW_EVENTS\n\n" >> "$FINAL_REPORT_FILE"
    fi
done

# If any key found a suspicious event, send the combined report.
if [ $HAS_EVENTS -eq 1 ]; then
    EMAIL_SUBJECT="CRITICAL: Security Audit Alert on $(hostname)"
    EMAIL_BODY="A high-risk audit rule was triggered. This indicates a critical file change or a suspicious PHP file creation.\n\n"
    EMAIL_BODY+=$(cat "$FINAL_REPORT_FILE")

    echo -e "$EMAIL_BODY" | mail -s "$EMAIL_SUBJECT" "$EMAIL_TO"
fi

exit 0
