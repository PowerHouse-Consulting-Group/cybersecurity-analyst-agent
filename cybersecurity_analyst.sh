#!/bin/bash

# =================================================================
# Gemini CLI - AI Cybersecurity Log Analyst
# =================================================================

# --- Configuration Loader ---
# Find the directory of this script to load the local .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Configuration file not found at $ENV_FILE"
    echo "Please copy .env.example to .env and configure your variables."
    exit 1
fi

# Load variables from .env
set -a
source "$ENV_FILE"
set +a

# --- Validate Required Variables ---
REQUIRED_VARS=("YOUR_EMAIL" "PROJECT_ID" "MODEL_ID" "APACHE_LOG_DIR" "SYSTEM_LOG_PATH" "MAIL_LOG_PATH")
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        echo "ERROR: Missing required configuration variable: $VAR"
        exit 1
    fi
done

MODEL_API_URL="https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/publishers/google/models/${MODEL_ID}:streamGenerateContent"

# Defaults if not provided in .env
KEYWORDS="${KEYWORDS:-error|warning|denied|blocked|failed|crashed|critical}"
TOP_N="${TOP_N:-20}"
MAX_LINE_LENGTH="${MAX_LINE_LENGTH:-500}"
REMEDIATION_DIR="${REMEDIATION_DIR:-/opt/ai-soc/remediation_scripts}"
NOISE_FILTER="${NOISE_FILTER:-favicon\.ico|robots\.txt|apple-touch-icon|AH00124|AH01071|File does not exist: /var/www/html}"

# --- Lockfile and Temp File Setup ---
LOCKFILE="/tmp/daily_log_analyst.lock"
if [ -e "$LOCKFILE" ]; then exit 1; fi
touch "$LOCKFILE"
JSON_PAYLOAD_FILE=$(mktemp /tmp/gemini_payload.XXXXXX.json)
RAW_RESPONSE_FILE=$(mktemp /tmp/gemini_response.XXXXXX.json)
trap 'rm -f "$LOCKFILE" "$JSON_PAYLOAD_FILE" "$RAW_RESPONSE_FILE"; exit $?' INT TERM EXIT

# --- Date Calculation for "Weekly" Scope ---
CURRENT_MONTH=$(date +'%b')
DATE_PATTERN="^${CURRENT_MONTH}"

echo "Starting weekly log analysis for date pattern: '${DATE_PATTERN}'"

# --- 1. Gather & Pre-Summarize Log Data ---
SUMMARY_DATA=""

echo "--> Analyzing Web Server Logs..."
APACHE_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo find "$APACHE_LOG_DIR" -type f -name "*.error.log" -mtime -7 
    -exec nice -n 19 ionice -c 2 -n 7 grep -H -E "$KEYWORDS" {} + 2>/dev/null 
    | grep -vE "$NOISE_FILTER" 
    | cut -c 1-"$MAX_LINE_LENGTH" 
    | sort 
    | uniq -c 
    | sort -nr 
    | head -n "$TOP_N")

if [ -n "$APACHE_ERRORS" ]; then
    SUMMARY_DATA+="### Top Web Server Errors (Count | FilePath:LogLine):
${APACHE_ERRORS}

"
fi

echo "--> Analyzing System & Firewall Logs..."
if [ -f "$SYSTEM_LOG_PATH" ]; then
    SYSTEM_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo grep -E "$DATE_PATTERN" "$SYSTEM_LOG_PATH" 2>/dev/null 
        | grep -iE "$KEYWORDS" 
        | cut -c 1-"$MAX_LINE_LENGTH" 
        | sort 
        | uniq -c 
        | sort -nr 
        | head -n "$TOP_N")

    if [ -n "$SYSTEM_ERRORS" ]; then
        SUMMARY_DATA+="### Top System/Firewall Events (Count | Message):
${SYSTEM_ERRORS}

"
    fi
fi

echo "--> Analyzing Mail Logs..."
if [ -f "$MAIL_LOG_PATH" ]; then
    MAIL_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo grep -E "$DATE_PATTERN" "$MAIL_LOG_PATH" 2>/dev/null 
        | grep -iE "$KEYWORDS" 
        | cut -c 1-"$MAX_LINE_LENGTH" 
        | sort 
        | uniq -c 
        | sort -nr 
        | head -n "$TOP_N")

    if [ -n "$MAIL_ERRORS" ]; then
        SUMMARY_DATA+="### Top Mail Log Events (Count | Message):
${MAIL_ERRORS}

"
    fi
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
At the very end of your response, include a **purely executable BASH script block** wrapped in ```bash ... ```.
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

```bash
#!/bin/bash
# Auto-generated remediation script
# ... commands ...
```

Here is the log data:
EOP
)

JSON_TEXT_CONTENT=$(printf "%s

%s" "$PROMPT" "$SUMMARY_DATA" | jq -R -s '.')

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
    
FINAL_REPORT=$(jq -j '.[].candidates[0].content.parts[0].text' "$RAW_RESPONSE_FILE" 2>/dev/null)

# --- 3a. Extract Remediation Script ---
mkdir -p "$REMEDIATION_DIR"
REMEDIATION_FILE="${REMEDIATION_DIR}/remediation_$(date +%F).sh"
echo "$FINAL_REPORT" | sed -n '/^```bash$/,/^```$/p' | sed '1d;$d' > "$REMEDIATION_FILE"

SCRIPT_MSG=""
if [ -s "$REMEDIATION_FILE" ]; then
    chmod +x "$REMEDIATION_FILE"
    sed -i '1i #!/bin/bash
# --- WARNING: AUTO-GENERATED SCRIPT ---
# Review carefully before running!
# Generated by weekly_log_analyst.sh
' "$REMEDIATION_FILE"
    SCRIPT_MSG="<br><hr><h3>🤖 Auto-Remediation Script Generated</h3><p>An actionable bash script has been created at: <b>$REMEDIATION_FILE</b></p><p>Please review it and run: <code>bash $REMEDIATION_FILE</code> to apply fixes.</p>"
else
    rm -f "$REMEDIATION_FILE"
fi

# --- 4. Email the Report ---
if [[ -z "$FINAL_REPORT" || "$FINAL_REPORT" == "null" ]]; then
    ERROR_DETAILS=$(jq '.' "$RAW_RESPONSE_FILE")
    FINAL_REPORT="Failed to get a valid analysis from the Gemini API. The raw API response was:
----------------------------------------
${ERROR_DETAILS}"
    
    echo -e "$FINAL_REPORT" | mail -s "ACTION FAILED: Gemini Log Analyst on $(hostname)" "$YOUR_EMAIL"
else
    if command -v markdown &> /dev/null; then
        HTML_BODY=$(echo "$FINAL_REPORT" | markdown)
        HTML_BODY="${HTML_BODY}${SCRIPT_MSG}"
        CONTENT_TYPE="text/html"
    else
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