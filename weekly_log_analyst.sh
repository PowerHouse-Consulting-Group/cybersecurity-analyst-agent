#!/bin/bash

# =================================================================
# Gemini CLI - Daily Log Analyst (v9 - Senior Admin Optimized)
# Improvements:
# - Preserves filename/domain context for Apache logs
# - Strict date-based filtering (no more "last 10k lines" guessing)
# - Truncates massive log lines to save API tokens
# - Fallback for missing 'markdown' command
# =================================================================

# --- Configuration ---
YOUR_EMAIL="vasilis@powerhouseconsulting.group, alex@powerhouseconsulting.group"
MODEL_ID="gemini-3-pro-preview"
PROJECT_ID="powerhouseconsulting"
MODEL_API_URL="https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/publishers/google/models/${MODEL_ID}:streamGenerateContent"
KEYWORDS="error|warning|denied|blocked|failed|crashed|critical"
# ... rest of configuration ...
TOP_N=20
MAX_LINE_LENGTH=500 # Truncate log lines to this length to save tokens
# --- End Configuration ---

# --- Lockfile and Temp File Setup ---
LOCKFILE="/tmp/daily_log_analyst.lock"
if [ -e "$LOCKFILE" ]; then exit 1; fi
touch "$LOCKFILE"
JSON_PAYLOAD_FILE=$(mktemp /tmp/gemini_payload.XXXXXX.json)
RAW_RESPONSE_FILE=$(mktemp /tmp/gemini_response.XXXXXX.json)
trap 'rm -f "$LOCKFILE" "$JSON_PAYLOAD_FILE" "$RAW_RESPONSE_FILE"; exit $?' INT TERM EXIT

# --- Date Calculation for "Weekly" Scope ---
# We use the current month pattern to catch recent logs (e.g., "Jan").
# For Apache logs, we look back 7 days using find -mtime -7.
CURRENT_MONTH=$(date +'%b')
DATE_PATTERN="^${CURRENT_MONTH}"

echo "Starting weekly log analysis for date pattern: '${DATE_PATTERN}'"

# --- 1. Gather & Pre-Summarize Log Data ---
SUMMARY_DATA=""
# Noise filters to save tokens: Exclude favicon/robots 404s, internal redirect loops (usually benign config), and common noise.
NOISE_FILTER="favicon\.ico|robots\.txt|apple-touch-icon|AH00124|AH01071|File does not exist: /var/www/html"

echo "--> Analyzing Apache/ModSecurity/PHP Logs..."
# IMPROVEMENT: Used 'grep -H' to keep the filename. Now AI knows which domain is hit.
# IMPROVEMENT: 'cut -c 1-"$MAX_LINE_LENGTH"' truncates long attack payloads.
# IMPROVEMENT: Added grep -vE "$NOISE_FILTER" to reduce input token usage.
# IMPROVEMENT: Changed -mtime -1 (daily) to -mtime -7 (weekly)
APACHE_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo find /usr/local/apache/domlogs/ -type f -name "*.error.log" -mtime -7 \
    -exec nice -n 19 ionice -c 2 -n 7 grep -H -E "$KEYWORDS" {} + \
    | grep -vE "$NOISE_FILTER" \
    | cut -c 1-"$MAX_LINE_LENGTH" \
    | sort \
    | uniq -c \
    | sort -nr \
    | head -n "$TOP_N")

if [ -n "$APACHE_ERRORS" ]; then
    SUMMARY_DATA+="### Top Apache/ModSecurity/PHP Errors (Count | FilePath:LogLine):\n${APACHE_ERRORS}\n\n"
fi

echo "--> Analyzing System & Firewall (CSF) Logs..."
# IMPROVEMENT: Grep for the specific Date Pattern first, then keywords.
SYSTEM_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo grep -E "$DATE_PATTERN" /var/log/messages \
    | grep -iE "$KEYWORDS" \
    | cut -c 1-"$MAX_LINE_LENGTH" \
    | sort \
    | uniq -c \
    | sort -nr \
    | head -n "$TOP_N")

if [ -n "$SYSTEM_ERRORS" ]; then
    SUMMARY_DATA+="### Top System/Firewall Events (Count | Message):\n${SYSTEM_ERRORS}\n\n"
fi

echo "--> Analyzing Mail Logs..."
# IMPROVEMENT: Grep for the specific Date Pattern first.
MAIL_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo grep -E "$DATE_PATTERN" /var/log/maillog \
    | grep -iE "$KEYWORDS" \
    | cut -c 1-"$MAX_LINE_LENGTH" \
    | sort \
    | uniq -c \
    | sort -nr \
    | head -n "$TOP_N")

if [ -n "$MAIL_ERRORS" ]; then
    SUMMARY_DATA+="### Top Mail Log Events (Count | Message):\n${MAIL_ERRORS}\n\n"
fi

# --- 2. Decide Whether to Call the API ---
if [ -z "$SUMMARY_DATA" ]; then
    echo "Pre-check complete. No new notable events found for this week."
    exit 0
fi

# --- 3. Craft Prompt and Send to API ---
PROMPT=$(cat <<'EOP'
You are a Senior Linux Server Cybersecurity Analyst.
Your goal is to digest the provided server logs from the last week and produce a concise, high-value intelligence report for the Chief Information Security Officer (CISO).

**Directives:**
1.  **Identify the TOP 3 Critical Issues:** Do not list everything. Pick the 3 most dangerous or impactful events (e.g., active intrusions, root compromises, mass exploits, critical service failures). Ignore routine noise.
2.  **Analysis, Not Description:** For each of the Top 3, explain *what* the attacker is trying to do and *why* it matters.
3.  **Actionable Remediation:** Provide exact `csf` commands, file edits, or checks to mitigate these 3 issues.
4.  **Brevity is Key:** Keep the response short and dense. No fluff.

**5. Remediation Script (Auto-Generated):**
At the very end of your response, include a **purely executable BASH script block** wrapped in \`\`\`bash ... \`\`\`.
- This script must contain the exact commands (`csf -d`, `chmod`, `chown`, `kill`) to fix the Critical issues identified.
- Add comments explaining each action.
- **SAFETY FIRST:** Do not include dangerous commands like `rm -rf /` or `iptables --flush`. Use `csf` for blocking.
- Start the block with `#!/bin/bash`.

**Format:**
# 🛡️ Senior Analyst Security Briefing (Weekly)
**Date:** (Insert Date)

## 🚨 Top 3 Critical Priorities
... (Analysis) ...

## 📉 Routine Noise Summary
... (Summary) ...

\`\`\`bash
#!/bin/bash
# Auto-generated remediation script
# ... commands ...
\`\`\`

Here is the log data:
EOP
)

# IMPROVEMENT: Use printf for safe string handling
JSON_TEXT_CONTENT=$(printf "%s\n\n%s" "$PROMPT" "$SUMMARY_DATA" | jq -R -s '.')

cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "contents": [{
    "role": "user",
    "parts": [{ "text": ${JSON_TEXT_CONTENT} }]
  }]
}
EOF

echo "Sending summarized logs to Gemini for analysis..."
curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" "$MODEL_API_URL" -d @"$JSON_PAYLOAD_FILE" > "$RAW_RESPONSE_FILE"
    
# Use jq -j to join the text parts from the streaming response array
FINAL_REPORT=$(jq -j '.[].candidates[0].content.parts[0].text' "$RAW_RESPONSE_FILE" 2>/dev/null)

# --- 3a. Extract Remediation Script ---
REMEDIATION_DIR="/root/remediation_scripts"
mkdir -p "$REMEDIATION_DIR"
REMEDIATION_FILE="${REMEDIATION_DIR}/remediation_$(date +%F).sh"
# Extract content between ```bash and ``` lines
echo "$FINAL_REPORT" | sed -n '/^```bash$/,/^```$/p' | sed '1d;$d' > "$REMEDIATION_FILE"

SCRIPT_MSG=""
if [ -s "$REMEDIATION_FILE" ]; then
    chmod +x "$REMEDIATION_FILE"
    # Prepend a safety warning/header to the script
    sed -i '1i #!/bin/bash\n# --- WARNING: AUTO-GENERATED SCRIPT ---\n# Review carefully before running!\n# Generated by weekly_log_analyst.sh\n' "$REMEDIATION_FILE"
    SCRIPT_MSG="<br><hr><h3>🤖 Auto-Remediation Script Generated</h3><p>An actionable bash script has been created at: <b>$REMEDIATION_FILE</b></p><p>Please review it and run: <code>bash $REMEDIATION_FILE</code> to apply fixes.</p>"
else
    rm -f "$REMEDIATION_FILE"
fi

# --- 4. Email the Report ---
if [[ -z "$FINAL_REPORT" || "$FINAL_REPORT" == "null" ]]; then
    ERROR_DETAILS=$(jq '.' "$RAW_RESPONSE_FILE")
    FINAL_REPORT="Failed to get a valid analysis from the Gemini API. The raw API response was:\n----------------------------------------\n${ERROR_DETAILS}"
    
    # Send text-only error
    echo -e "$FINAL_REPORT" | mail -s "ACTION FAILED: Gemini Log Analyst on $(hostname)" "$YOUR_EMAIL"
else
    # IMPROVEMENT: Fallback if 'markdown' command is missing (User confirmed it's installed, but good practice to keep fallback)
    if command -v markdown &> /dev/null; then
        HTML_BODY=$(echo "$FINAL_REPORT" | markdown)
        HTML_BODY="${HTML_BODY}${SCRIPT_MSG}" # Append script msg
        CONTENT_TYPE="text/html"
    else
        # Wrap in <pre> so it's readable if the client renders HTML, or just send as text
        HTML_BODY="<html><body><h3>Markdown renderer not found. Raw Report:</h3><pre>${FINAL_REPORT}</pre>${SCRIPT_MSG}</body></html>"
        CONTENT_TYPE="text/html"
    fi

    (
        echo "To: $YOUR_EMAIL"
        echo "Subject: Weekly Server Security Briefing for $(hostname)"
        echo "MIME-Version: 1.0"
        echo "Content-Type: $CONTENT_TYPE"
        echo ""
        echo "$HTML_BODY"
    ) | /usr/sbin/sendmail -t
fi

echo "Log analysis complete. Report sent."