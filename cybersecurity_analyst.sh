#!/bin/bash

# =================================================================
# Gemini CLI - AI Cybersecurity Log Analyst
# Modularized with Nginx Support & Interactive CLI Mode
# =================================================================
# IP License holder and point of contact:
# PowerHouse Consulting Group Pte Ltd
# 160 Robinson Road
# SBF Center Unit #24-09,
# 068914, Singapore
# ACRA UEN 202108925N
# support (at) powerhouseconsulting.group
# =================================================================

# --- Global Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
LOCKFILE="/tmp/daily_log_analyst.lock"
JSON_PAYLOAD_FILE=$(mktemp /tmp/gemini_payload.XXXXXX.json)
RAW_RESPONSE_FILE=$(mktemp /tmp/gemini_response.XXXXXX.json)
CURRENT_MONTH=$(date +'%b')
DATE_PATTERN="^${CURRENT_MONTH}"
INTERACTIVE=0
SUMMARY_DATA=""
FINAL_REPORT=""
SCRIPT_MSG=""
REMEDIATION_FILE=""

# Ensure cleanup on exit
trap 'err=$?; rm -f "$LOCKFILE" "$JSON_PAYLOAD_FILE" "$RAW_RESPONSE_FILE"; exit $err' INT TERM EXIT

# --- Functions ---

# Print messages conditionally based on interactive mode
log_info() {
    echo -e "[INFO] $1"
}

log_error() {
    echo -e "[ERROR] $1" >&2
}

# 1. Configuration Loader
load_config() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Configuration file not found at $ENV_FILE"
        log_error "Please copy .env.example to .env and configure your variables."
        exit 1
    fi

    set -a
    source "$ENV_FILE"
    set +a

    # Validate Required Variables
    local REQUIRED_VARS=("YOUR_EMAIL" "PROJECT_ID" "MODEL_ID")
    for VAR in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!VAR}" ]; then
            log_error "Missing required configuration variable: $VAR"
            exit 1
        fi
    done

    # Setup Defaults
    KEYWORDS="${KEYWORDS:-error|warning|denied|blocked|failed|crashed|critical}"
    TOP_N="${TOP_N:-20}"
    MAX_LINE_LENGTH="${MAX_LINE_LENGTH:-500}"
    REMEDIATION_DIR="${REMEDIATION_DIR:-/opt/ai-soc/remediation_scripts}"
    NOISE_FILTER="${NOISE_FILTER:-favicon\.ico|robots\.txt|apple-touch-icon|AH00124|AH01071|File does not exist: /var/www/html}"
    MODEL_API_URL="https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/publishers/google/models/${MODEL_ID}:streamGenerateContent"
}

# 2. Parse Server Logs
parse_logs() {
    log_info "Starting weekly log analysis for date pattern: '${DATE_PATTERN}'"

    # Apache Logs
    if [[ -n "$APACHE_LOG_DIR" && -d "$APACHE_LOG_DIR" ]]; then
        log_info "--> Analyzing Apache/ModSecurity Logs in $APACHE_LOG_DIR..."
        APACHE_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo find "$APACHE_LOG_DIR" -type f -name "*.error.log" -mtime -7 \
            -exec nice -n 19 ionice -c 2 -n 7 grep -H -E "$KEYWORDS" {} + 2>/dev/null \
            | grep -vE "$NOISE_FILTER" \
            | cut -c 1-"$MAX_LINE_LENGTH" \
            | sort \
            | uniq -c \
            | sort -nr \
            | head -n "$TOP_N")

        if [ -n "$APACHE_ERRORS" ]; then
            SUMMARY_DATA+="### Top Apache Web Server Errors (Count | FilePath:LogLine):\n${APACHE_ERRORS}\n\n"
        fi
    fi

    # Nginx Logs
    if [[ -n "$NGINX_LOG_DIR" && -d "$NGINX_LOG_DIR" ]]; then
        log_info "--> Analyzing Nginx Logs in $NGINX_LOG_DIR..."
        NGINX_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo find "$NGINX_LOG_DIR" -type f -name "*.error.log" -mtime -7 \
            -exec nice -n 19 ionice -c 2 -n 7 grep -H -E "$KEYWORDS" {} + 2>/dev/null \
            | grep -vE "$NOISE_FILTER" \
            | cut -c 1-"$MAX_LINE_LENGTH" \
            | sort \
            | uniq -c \
            | sort -nr \
            | head -n "$TOP_N")

        if [ -n "$NGINX_ERRORS" ]; then
            SUMMARY_DATA+="### Top Nginx Web Server Errors (Count | FilePath:LogLine):\n${NGINX_ERRORS}\n\n"
        fi
    fi

    # System & Firewall Logs
    if [[ -n "$SYSTEM_LOG_PATH" && -f "$SYSTEM_LOG_PATH" ]]; then
        log_info "--> Analyzing System & Firewall Logs ($SYSTEM_LOG_PATH)..."
        SYSTEM_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo grep -E "$DATE_PATTERN" "$SYSTEM_LOG_PATH" 2>/dev/null \
            | grep -iE "$KEYWORDS" \
            | cut -c 1-"$MAX_LINE_LENGTH" \
            | sort \
            | uniq -c \
            | sort -nr \
            | head -n "$TOP_N")

        if [ -n "$SYSTEM_ERRORS" ]; then
            SUMMARY_DATA+="### Top System/Firewall Events (Count | Message):\n${SYSTEM_ERRORS}\n\n"
        fi
    fi

    # Journalctl Logs (systemd)
    if [[ "$USE_JOURNALCTL" == "true" ]]; then
        log_info "--> Analyzing Journalctl System Logs (Last 7 days)..."
        JOURNAL_ERRORS=$(nice -n 19 ionice -c 2 -n 7 journalctl -p 0..3 --since "7 days ago" --no-pager 2>/dev/null \
            | grep -vE "$NOISE_FILTER" \
            | cut -c 1-"$MAX_LINE_LENGTH" \
            | sort \
            | uniq -c \
            | sort -nr \
            | head -n "$TOP_N")

        if [ -n "$JOURNAL_ERRORS" ]; then
            SUMMARY_DATA+="### Top Journalctl Priority Events (Count | Message):\n${JOURNAL_ERRORS}\n\n"
        fi
    fi

    # MySQL/MariaDB Slow Query Logs
    local SLOW_LOG="$MYSQL_SLOW_LOG_PATH"
    if [[ -z "$SLOW_LOG" ]]; then
        # Auto-detect if empty
        SLOW_LOG=$(mysql -e "SHOW VARIABLES LIKE 'slow_query_log_file';" -sN 2>/dev/null | awk '{print $2}')
    fi

    if [[ -n "$SLOW_LOG" && -f "$SLOW_LOG" ]]; then
        log_info "--> Analyzing MySQL/MariaDB Slow Query Logs ($SLOW_LOG)..."
        MYSQL_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo tail -n 5000 "$SLOW_LOG" 2>/dev/null \
            | grep -iE "User@Host|Query_time|SET timestamp" -A 1 \
            | grep -vE "\-\-" \
            | head -n 1000 \
            | cut -c 1-"$MAX_LINE_LENGTH")

        if [ -n "$MYSQL_ERRORS" ]; then
            SUMMARY_DATA+="### MySQL/MariaDB Slow Query Samples:\n${MYSQL_ERRORS}\n\n"
        fi
    fi

    # Mail Logs
    if [[ -n "$MAIL_LOG_PATH" && -f "$MAIL_LOG_PATH" ]]; then
        log_info "--> Analyzing Mail Logs ($MAIL_LOG_PATH)..."
        MAIL_ERRORS=$(nice -n 19 ionice -c 2 -n 7 sudo grep -E "$DATE_PATTERN" "$MAIL_LOG_PATH" 2>/dev/null \
            | grep -iE "$KEYWORDS" \
            | cut -c 1-"$MAX_LINE_LENGTH" \
            | sort \
            | uniq -c \
            | sort -nr \
            | head -n "$TOP_N")

        if [ -n "$MAIL_ERRORS" ]; then
            SUMMARY_DATA+="### Top Mail Log Events (Count | Message):\n${MAIL_ERRORS}\n\n"
        fi
    fi

    if [ -z "$SUMMARY_DATA" ]; then
        log_info "Pre-check complete. No new notable events found for this week."
        exit 0
    fi
}

# 3. Analyze with AI (Multi-LLM Support)
analyze_with_ai() {
    local PROMPT=$(cat <<'EOP'
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

    local JSON_TEXT_CONTENT=$(printf "%s\n\n%s" "$PROMPT" "$SUMMARY_DATA" | jq -R -s '.')
    log_info "Sending summarized logs to $LLM_PROVIDER for analysis..."

    case "$LLM_PROVIDER" in
        "gemini")
            cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "contents": [{
    "role": "user",
    "parts": [{ "text": ${JSON_TEXT_CONTENT} }]
  }]
}
EOF
            curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" -H "Content-Type: application/json" "https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/publishers/google/models/${MODEL_ID}:streamGenerateContent" -d @"$JSON_PAYLOAD_FILE" > "$RAW_RESPONSE_FILE"
            FINAL_REPORT=$(jq -j '.[].candidates[0].content.parts[0].text' "$RAW_RESPONSE_FILE" 2>/dev/null)
            ;;

        "openai"|"local")
            cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "model": "${OPENAI_MODEL_ID}",
  "messages": [
    {
      "role": "user",
      "content": ${JSON_TEXT_CONTENT}
    }
  ]
}
EOF
            curl -s -X POST -H "Authorization: Bearer ${OPENAI_API_KEY}" -H "Content-Type: application/json" "${OPENAI_API_URL}" -d @"$JSON_PAYLOAD_FILE" > "$RAW_RESPONSE_FILE"
            FINAL_REPORT=$(jq -j '.choices[0].message.content' "$RAW_RESPONSE_FILE" 2>/dev/null)
            ;;

        "claude")
            cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "model": "${CLAUDE_MODEL_ID}",
  "max_tokens": 4096,
  "messages": [
    {
      "role": "user",
      "content": ${JSON_TEXT_CONTENT}
    }
  ]
}
EOF
            curl -s -X POST -H "x-api-key: ${CLAUDE_API_KEY}" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" "https://api.anthropic.com/v1/messages" -d @"$JSON_PAYLOAD_FILE" > "$RAW_RESPONSE_FILE"
            FINAL_REPORT=$(jq -j '.content[0].text' "$RAW_RESPONSE_FILE" 2>/dev/null)
            ;;

        *)
            log_error "Unknown LLM_PROVIDER: $LLM_PROVIDER"
            exit 1
            ;;
    esac

    if [[ -z "$FINAL_REPORT" || "$FINAL_REPORT" == "null" ]]; then
        local ERROR_DETAILS=$(cat "$RAW_RESPONSE_FILE")
        FINAL_REPORT="Failed to get a valid analysis from the API. The raw API response was:\n----------------------------------------\n${ERROR_DETAILS}"
        log_error "API Error occurred during communication with $LLM_PROVIDER."
        return 1
    fi
}

# 4. Extract and Process Remediation Script
process_remediation() {
    mkdir -p "$REMEDIATION_DIR"
    REMEDIATION_FILE="${REMEDIATION_DIR}/remediation_$(date +%F_%H%M%S).sh"
    
    # Extract content between ```bash and ``` lines
    echo "$FINAL_REPORT" | sed -n '/^```bash$/,/^```$/p' | sed '1d;$d' > "$REMEDIATION_FILE"

    if [ -s "$REMEDIATION_FILE" ]; then
        chmod +x "$REMEDIATION_FILE"
        sed -i '1i #!/bin/bash
# --- WARNING: AUTO-GENERATED SCRIPT ---
# Review carefully before running!
# Generated by AI Cybersecurity Log Analyst
' "$REMEDIATION_FILE"
        SCRIPT_MSG="<br><hr><h3>🤖 Auto-Remediation Script Generated</h3><p>An actionable bash script has been created at: <b>$REMEDIATION_FILE</b></p><p>Please review it and run: <code>bash $REMEDIATION_FILE</code> to apply fixes.</p>"
        log_info "Remediation script generated at: $REMEDIATION_FILE"
    else
        rm -f "$REMEDIATION_FILE"
        REMEDIATION_FILE=""
    fi
}

# 5. Send Report / Handle Interactive Mode
handle_output() {
    if [ "$INTERACTIVE" -eq 1 ]; then
        echo -e "
========================================================"
        echo -e "🛡️  GEMINI AI SOC REPORT"
        echo -e "========================================================
"
        
        # Display Markdown to Terminal
        if command -v markdown &> /dev/null; then
            # Not ideal for terminal, but better than raw if they have a terminal markdown viewer like 'glow' or 'bat'.
            # Falling back to raw text for terminal clarity
            echo -e "$FINAL_REPORT"
        else
            echo -e "$FINAL_REPORT"
        fi
        
        if [ -n "$REMEDIATION_FILE" ]; then
            echo -e "
--------------------------------------------------------"
            echo -e "⚠️  AUTO-REMEDIATION SCRIPT GENERATED"
            echo -e "Location: $REMEDIATION_FILE"
            echo -e "--------------------------------------------------------
"
            cat "$REMEDIATION_FILE"
            echo -e "
"
            read -p "Do you want to execute this remediation script now? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                log_info "Executing remediation script..."
                sudo bash "$REMEDIATION_FILE"
                log_info "Execution complete."
            else
                log_info "Execution aborted. You can run it manually later."
            fi
        fi
    else
        # Cron/Non-Interactive Mode - Send Email
        local CONTENT_TYPE="text/html"
        local HTML_BODY=""

        if command -v markdown &> /dev/null; then
            HTML_BODY=$(echo "$FINAL_REPORT" | markdown)
            HTML_BODY="${HTML_BODY}${SCRIPT_MSG}"
        else
            HTML_BODY="<html><body><h3>Markdown renderer not found. Raw Report:</h3><pre>${FINAL_REPORT}</pre>${SCRIPT_MSG}</body></html>"
        fi

        (
            echo "To: $YOUR_EMAIL"
            echo "Subject: Weekly Server Security Briefing for $(hostname)"
            echo "MIME-Version: 1.0"
            echo "Content-Type: $CONTENT_TYPE"
            echo ""
            echo "$HTML_BODY"
        ) | /usr/sbin/sendmail -t
        
        log_info "Log analysis complete. Report sent to $YOUR_EMAIL."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

# --- Main Execution Flow ---

# Check for lockfile
if [ -e "$LOCKFILE" ]; then
    log_error "Script is already running (lockfile exists: $LOCKFILE)."
    exit 1
fi
touch "$LOCKFILE"

# Parse CLI Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --interactive|-i) INTERACTIVE=1 ;;
        *) log_error "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

load_config
parse_logs
if analyze_with_ai; then
    process_remediation
    handle_output
fi
fi

