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
VERSION="v1.1.2"
umask 077
JSON_PAYLOAD_FILE=$(mktemp /tmp/gemini_payload.XXXXXX.json)
RAW_RESPONSE_FILE=$(mktemp /tmp/gemini_response.XXXXXX.json)
CURRENT_MONTH=$(date +'%b')
DATE_PATTERN="^${CURRENT_MONTH}"
INTERACTIVE=1
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

scrub_pii() {
    local input="$1"
    # Mask IPv4 addresses
    input=$(echo "$input" | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[REDACTED_IP]/g')
    # Mask standard Email addresses
    input=$(echo "$input" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g')
    echo "$input"
}

# 1. Configuration Loader
load_config() {
    if [ ! -f "$ENV_FILE" ]; then
        # First run: copy example and guide
        echo -e "\n\e[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
        echo -e "\e[1;37m  ⚙️  FIRST-TIME SETUP — Configuration Required\e[0m"
        echo -e "\e[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
        echo -e "\n\e[1;36m[INFO]\e[0m No configuration file found at \e[1;33m$ENV_FILE\e[0m"
        echo -e "\e[1;36m[INFO]\e[0m Creating default .env from template..."
        cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
        echo -e "\e[1;32m[OK]\e[0m Created: \e[1;33m$ENV_FILE\e[0m"
        echo -e "\n\e[1;37mYou MUST configure the following before running scans:\e[0m"
        echo -e "  \e[1;32m1.\e[0m \e[1;37mYOUR_EMAIL\e[0m        — Where reports are sent"
        echo -e "  \e[1;32m2.\e[0m \e[1;37mLLM_PROVIDER\e[0m      — AI provider (gemini, openai, claude, local)"
        echo -e "  \e[1;32m3.\e[0m \e[1;37mMODEL_ID\e[0m          — AI model to use"
        echo -e "  \e[1;32m4.\e[0m \e[1;37mAPI Key\e[0m           — Your provider's API key"
        echo -e "  \e[1;32m5.\e[0m \e[1;37mLog Paths\e[0m         — Paths to your server logs"
        echo -e "\n\e[1;36mEdit the file:\e[0m"
        echo -e "  \e[1;33mnano $ENV_FILE\e[0m"
        echo -e "\n\e[1;36mThen re-run:\e[0m"
        echo -e "  \e[1;33mcsa\e[0m"
        echo -e "\e[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n"
        exit 1
    fi

    set -a
    source "$ENV_FILE"
    set +a

    # Validate Required Variables
    local REQUIRED_VARS=("YOUR_EMAIL" "MODEL_ID")
    local MISSING_VARS=()
    for VAR in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!VAR}" ]; then
            MISSING_VARS+=("$VAR")
        fi
    done

    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo -e "\n\e[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
        echo -e "\e[1;37m  ⚠️  CONFIGURATION INCOMPLETE\e[0m"
        echo -e "\e[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
        echo -e "\n\e[1;31m[ERROR]\e[0m The following required variables are missing or empty:"
        for VAR in "${MISSING_VARS[@]}"; do
            echo -e "  \e[1;31m✗\e[0m \e[1;37m$VAR\e[0m"
        done
        echo -e "\n\e[1;36mEdit:\e[0m \e[1;33mnano $ENV_FILE\e[0m"
        echo -e "\e[1;36mRe-run:\e[0m \e[1;33mcsa\e[0m"
        echo -e "\e[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n"
        exit 1
    fi

    # Ensure authentication for Gemini is set up via either API Key or GCP Project ID
    if [[ "$LLM_PROVIDER" == "gemini" ]] && [ -z "$GEMINI_API_KEY" ] && [ -z "$PROJECT_ID" ]; then
        echo -e "\n\e[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
        echo -e "\e[1;37m  ⚠️  MISSING GEMINI CREDENTIALS\e[0m"
        echo -e "\e[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
        echo -e "\n\e[1;31m[ERROR]\e[0m LLM_PROVIDER is set to 'gemini' but no credentials found."
        echo -e "Configure \e[1;37mGEMINI_API_KEY\e[0m (developer) or \e[1;37mPROJECT_ID\e[0m (GCP Vertex AI)."
        echo -e "\n\e[1;36mEdit:\e[0m \e[1;33mnano $ENV_FILE\e[0m"
        echo -e "\e[1;36mRe-run:\e[0m \e[1;33mcsa\e[0m"
        echo -e "\e[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n"
        exit 1
    fi

    # Setup Defaults
    KEYWORDS="${KEYWORDS:-error|warning|denied|blocked|failed|crashed|critical}"
    TOP_N="${TOP_N:-20}"
    MAX_LINE_LENGTH="${MAX_LINE_LENGTH:-500}"
    REMEDIATION_DIR="${REMEDIATION_DIR:-/opt/ai-soc/remediation_scripts}"
    NOISE_FILTER="${NOISE_FILTER:-favicon\\.ico|robots\\.txt|apple-touch-icon|AH00124|AH01071|File does not exist: /var/www/html}"
    MODEL_API_URL="https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/publishers/google/models/${MODEL_ID}:streamGenerateContent"
    }

check_dependencies() {
    local missing_deps=0
    
    if ! command -v jq &> /dev/null; then
        log_error "Critical dependency missing: 'jq'."
        log_error "Please install it via your package manager (e.g., sudo apt install jq or sudo dnf install jq)."
        missing_deps=1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "Critical dependency missing: 'curl'."
        log_error "Please install it via your package manager."
        missing_deps=1
    fi
    
    if [[ "$LLM_PROVIDER" == "gemini" ]] && [ -z "$GEMINI_API_KEY" ] && ! command -v gcloud &> /dev/null; then
        log_error "Critical dependency missing: 'gcloud' CLI."
        log_error "You selected 'gemini' as the LLM_PROVIDER but did not configure GEMINI_API_KEY. This requires the Google Cloud CLI (gcloud) to be installed and authenticated on this server for Vertex AI."
        missing_deps=1
    fi
    
    if [ "$INTERACTIVE" -eq 0 ] && [ ! -x "/usr/sbin/sendmail" ]; then
        log_error "Critical dependency missing: '/usr/sbin/sendmail'."
        log_error "Cron (non-interactive) mode requires a working Mail Transfer Agent (MTA) like Postfix or Exim to send email reports."
        missing_deps=1
    fi

    if [ "$missing_deps" -eq 1 ]; then
        log_error "Exiting due to missing dependencies."
        exit 1
    fi
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

**5. Remediation Script (Proposed - Pending Admin Approval):**
At the very end of your response, include a **purely executable BASH script block** wrapped in ````bash ... ````.
- **EXPLICIT PERMISSION MANDATE:** You are an advisory tool. You must not assume this script will be run automatically. It is a PROPOSAL for the System Administrator. 
- **NEVER TOUCH DATABASES:** You are strictly forbidden from generating commands that modify databases (e.g., mysql, mariadb, pgsql). Any DB schema changes must be provided as text instructions for manual review only.
- **CORE SYSTEM INTEGRITY:** Do not propose modifications to core Linux system files (/etc/passwd, /etc/sudoers, etc.) or destructive commands (`rm`, `truncate`).
- **SAFETY FIRST:** Use `csf` or `ufw` for blocking. Add clear comments explaining exactly what each action does so the Admin can audit it.
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

    local SCRUBBED_DATA=$(scrub_pii "$SUMMARY_DATA")
    local JSON_TEXT_CONTENT=$(printf "%s\n\n%s" "$PROMPT" "$SCRUBBED_DATA" | jq -R -s '.')
    log_info "Sending summarized logs to $LLM_PROVIDER for analysis..."

    case "$LLM_PROVIDER" in
        "gemini")
            if [ -n "$GEMINI_API_KEY" ]; then
                # Standard developer Generative Language API
                cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "contents": [{
    "role": "user",
    "parts": [{ "text": ${JSON_TEXT_CONTENT} }]
  }]
}
EOF
                curl -s -X POST -H "Content-Type: application/json" \
                    "https://generativelanguage.googleapis.com/v1beta/models/${MODEL_ID}:generateContent?key=${GEMINI_API_KEY}" \
                    -d @"$JSON_PAYLOAD_FILE" > "$RAW_RESPONSE_FILE"
                FINAL_REPORT=$(jq -j '.candidates[0].content.parts[0].text' "$RAW_RESPONSE_FILE" 2>/dev/null)
            else
                # Fallback to GCP Vertex AI API
                cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "contents": [{
    "role": "user",
    "parts": [{ "text": ${JSON_TEXT_CONTENT} }]
  }]
}
EOF
                curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" -H "Content-Type: application/json" \
                    "https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/publishers/google/models/${MODEL_ID}:generateContent" \
                    -d @"$JSON_PAYLOAD_FILE" > "$RAW_RESPONSE_FILE"
                FINAL_REPORT=$(jq -j '.candidates[0].content.parts[0].text' "$RAW_RESPONSE_FILE" 2>/dev/null)
            fi
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
            # --- SECURITY AUDIT: Strict Allowlist Scanner ---
            # Only allow specific safe commands, comments, and echo statements
            local ALLOWED_CMDS="^(csf |ufw |chmod |chown |systemctl |kill |#|echo |exit |sudo csf|sudo ufw)"
            # Check all non-empty lines (skipping the shebang on line 1) for unauthorized commands
            local INVALID_CMDS=$(grep -vE '^[[:space:]]*$' "$REMEDIATION_FILE" | tail -n +2 | grep -vE "$ALLOWED_CMDS")
            
            if [ -n "$INVALID_CMDS" ]; then
                log_error "CRITICAL SECURITY ALERT: The AI generated a script containing unauthorized commands."
                log_error "The following commands are not on the safe allowlist:"
                echo -e "\e[31m$INVALID_CMDS\e[0m"
                log_error "Execution is BLOCKED. The script has been saved to $REMEDIATION_FILE for manual review."
                return 1
            fi

            echo -e "\n\e[33m⚠️ WARNING: You are about to execute an AI-generated script with ROOT privileges."
            echo -e "Although the script passed the strict allowlist scanner, prompt-injected or obfuscated payloads may still exist."
            echo -e "Review the commands above carefully for any malicious arguments or suspicious network activity.\e[0m\n"
            read -p "Do you explicitly trust and want to execute this remediation script now? (y/N): " confirm
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

    if [ "$INTERACTIVE" -eq 1 ]; then
        display_pro_upsell
    fi
}

# --- PRO Features Upsell Dashboard ---
display_pro_upsell() {
    echo -e "\n\e[1;36m┌──────────────────────────────────────────────────────────────────────────┐\e[0m"
    echo -e "\e[1;36m│\e[0m \e[1;37m🚀 UPGRADE TO CYBERSECURITY ANALYST PRO FOR ENTERPRISE DEFENSE\e[0m         \e[1;36m│\e[0m"
    echo -e "\e[1;36m├──────────────────────────────────────────────────────────────────────────┤\e[0m"
    echo -e "\e[1;36m│\e[0m \e[1;32m[PRO FEATURE]\e[0m \e[1;37mAI Threat Insight & OSINT Enrichment\e[0m                       \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[0;90mAuto-enrich attacker IPs via Shodan & AbuseIPDB for deep context.        \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m                                                                          \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[1;32m[PRO FEATURE]\e[0m \e[1;37mBlast Radius Timeline Correlation\e[0m                          \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[0;90mCross-correlate Nginx, Auth, and DB logs 5 mins before/after breaches.   \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m                                                                          \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[1;32m[PRO FEATURE]\e[0m \e[1;37mActive Deception & SSH Tarpitting\e[0m                          \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[0;90mRoute attackers to endlessh honeypots instead of just dropping packets.  \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m                                                                          \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[1;32m[PRO FEATURE]\e[0m \e[1;37mMITRE ATT&CK Mapping & Compliance PDFs\e[0m                    \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[0;90m1-Click executive reports for SOC2, PCI-DSS, and ISO27001 audits.        \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m                                                                          \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[1;32m[PRO FEATURE]\e[0m \e[1;37mCross-Server Global Fleet Defense\e[0m                         \e[1;36m│\e[0m"
    echo -e "\e[1;36m│\e[0m \e[0;90mSync firewall blocks across your entire server cluster instantly.        \e[1;36m│\e[0m"
    echo -e "\e[1;36m├──────────────────────────────────────────────────────────────────────────┤\e[0m"
    echo -e "\e[1;35m│\e[0m \e[1;33m👉 GET PRO TODAY: https://powerhouseconsulting.group/cybersecurity-analyst/#pricing\e[0m \e[1;35m│\e[0m"
    echo -e "\e[1;36m└──────────────────────────────────────────────────────────────────────────┘\e[0m\n"
}

# --- Header Logo ---
display_header() {
    # Design System: Cyberpunk Retro Terminal
    # Matrix Green / Neon Magenta / Cyan
    echo -e "\e[1;35m===========================================================================\e[0m"
    echo -e "\e[1;36m   ______      __                 \e[1;35m_____                      _ __       "
    echo -e "\e[1;36m  / ____/_  __/ /_  ___  _____   \e[1;35m/ ___/___  ________  ______(_) /___  __"
    echo -e "\e[1;36m / /   / / / / __ \/ _ \/ ___/   \e[1;35m\__ \/ _ \/ ___/ / / / ___/ / __/ / / /"
    echo -e "\e[1;36m/ /___/ /_/ / /_/ /  __/ /      \e[1;35m___/ /  __/ /__/ /_/ / /  / / /_/ /_/ / "
    echo -e "\e[1;36m\____/\__, /_.___/\___/_/      \e[1;35m/____/\___/\___/\__,_/_/  /_/\__/\__, /  "
    echo -e "\e[1;36m     /____/                                                    \e[1;35m/____/   \e[0m"
    echo -e "\e[1;35m===========================================================================\e[0m"
    echo -e "\e[1;37m        AI Cybersecurity Log Analyst - \e[1;32mCommunity Edition \e[1;36m$VERSION\e[0m"
    echo -e "\n"
}

interactive_menu() {
    while true; do
        echo -e "\n\e[1;35m[\e[1;36m SYSTEM MAIN MENU \e[1;35m]\e[0m"
        echo -e "\e[1;36m>\e[0m \e[1;32m1)\e[0m \e[1;37mStart Live Log Scan (Weekly Analysis)\e[0m"
        echo -e "\e[1;36m>\e[0m \e[1;32m2)\e[0m \e[1;37mProactive Hardening Audit\e[0m"
        echo -e "\e[1;36m>\e[0m \e[1;35m3)\e[0m \e[1;33m🔥 Upgrade to PRO Version (Activate License Key)\e[0m"
        echo -e "\e[1;36m>\e[0m \e[1;32m4)\e[0m \e[1;37mQuit Application\e[0m"
        echo -e "\e[1;35m-------------------------------------------------\e[0m"
        read -p "$(echo -e "\e[1;36m[INPUT]\e[0m Select an option [1-4]: ")" choice
        case $choice in
            1)
                echo -e "\n\e[1;33m[INFO] Starting Live Log Scan. Press Ctrl+C to interrupt and return to menu.\e[0m\n"
                (
                    trap 'echo -e "\n\e[1;33m[INFO] Scan interrupted by user. Returning to menu...\e[0m"; exit 130' INT
                    parse_logs
                    if analyze_with_ai; then
                        process_remediation
                        handle_output
                    fi
                )
                ;;
            2)
                echo -e "\n\e[1;35m[ \e[1;36mAUDIT INITIATED \e[1;35m]\e[0m Scanning system configuration...\n"
                
                local issues=0
                
                # Check SSH config
                echo -ne "  SSH root login disabled... "
                if grep -qE "^PermitRootLogin\s+no" /etc/ssh/sshd_config 2>/dev/null; then
                    echo -e "\e[1;32m✓\e[0m"
                else
                    echo -e "\e[1;31m✗\e[0m (root login allowed)"
                    ((issues++))
                fi
                
                echo -ne "  SSH password auth disabled... "
                if grep -qE "^PasswordAuthentication\s+no" /etc/ssh/sshd_config 2>/dev/null; then
                    echo -e "\e[1;32m✓\e[0m"
                else
                    echo -e "\e[1;31m✗\e[0m (password auth enabled)"
                    ((issues++))
                fi
                
                # Check firewall
                echo -ne "  Firewall active... "
                if command -v ufw &>/dev/null && ufw status | grep -q "Status: active" 2>/dev/null; then
                    echo -e "\e[1;32m✓\e[0m (UFW)"
                elif command -v csf &>/dev/null && csf -l &>/dev/null 2>&1; then
                    echo -e "\e[1;32m✓\e[0m (CSF)"
                elif command -v iptables &>/dev/null && iptables -L -n | grep -q "DROP\|REJECT" 2>/dev/null; then
                    echo -e "\e[1;32m✓\e[0m (iptables)"
                else
                    echo -e "\e[1;31m✗\e[0m (no active firewall detected)"
                    ((issues++))
                fi
                
                # Check fail2ban
                echo -ne "  Fail2ban active... "
                if systemctl is-active fail2ban &>/dev/null 2>&1; then
                    echo -e "\e[1;32m✓\e[0m"
                else
                    echo -e "\e[1;31m✗\e[0m (not running)"
                    ((issues++))
                fi
                
                # Check unattended-upgrades
                echo -ne "  Unattended security updates... "
                if systemctl is-active unattended-upgrades &>/dev/null 2>&1 || systemctl is-active dnf-automatic &>/dev/null 2>&1; then
                    echo -e "\e[1;32m✓\e[0m"
                else
                    echo -e "\e[1;33m!\e[0m (not installed — recommended)"
                fi
                
                # Check open ports
                echo -ne "  Open ports audit... "
                local open_ports=$(ss -tlnp 2>/dev/null | awk 'NR>1{print $4}' | sed 's/.*://' | sort -nu | tr '\n' ' ')
                if [ -n "$open_ports" ]; then
                    echo -e "\e[1;33m$open_ports\e[0m"
                else
                    echo -e "\e[1;32m✓\e[0m (minimal exposure)"
                fi
                
                echo ""
                if [ "$issues" -eq 0 ]; then
                    echo -e "\e[1;32m✅ No critical hardening issues detected. Your server is running in Stealth Mode.\e[0m"
                else
                    echo -e "\e[1;33m⚠️  $issues hardening issue(s) found. Review the ✗ items above.\e[0m"
                fi
                ;;
            3)
                echo -e "\n\e[1;35m===========================================================================\e[0m"
                echo -e "\e[1;37m🌟 UPGRADE TO CYBERSECURITY ANALYST PRO — ENTERPRISE DEFENSE\e[0m"
                echo -e "\e[1;35m===========================================================================\e[0m"
                echo -e "Our Go-based on-premise PRO dashboard runs directly in your SSH terminal and"
                echo -e "features real-time log scanning, asynchronous AI deep insight context, Slack/Discord"
                echo -e "notifications, and 1-click active IP blocking (CSF/UFW).\n"
                echo -e "How to Upgrade:"
                echo -e "1. Purchase a subscription at: \e[1;33mhttps://powerhouseconsulting.group/cybersecurity-analyst/#pricing\e[0m"
                echo -e "2. Copy your PRO-XXXX-XXXX-XXXX license key sent to your email."
                echo -e "3. Enter your license key below to instantly upgrade and activate PRO.\n"
                read -p "$(echo -e "\e[1;36m[INPUT]\e[0m Enter your License Key (or press Enter to cancel): ")" key
                if [ -n "$key" ]; then
                    echo -e "\n\e[1;32m[INFO] Contacting PowerHouse validation server...\e[0m"
                    curl -s "https://ptr.powerhouseconsulting.group/api/dist/install.sh" | sudo bash -s -- --key "$key"
                    exit 0
                else
                    echo -e "\n\e[1;33m[INFO] Activation cancelled. Returning to menu...\e[0m"
                fi
                ;;
            4)
                log_info "Exiting CyberSecurity Analyst."
                exit 0
                ;;
            *)
                log_error "Invalid option selected."
                ;;
        esac
    done
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
        --cron|-c) INTERACTIVE=0 ;;
        --interactive|-i) INTERACTIVE=1 ;;
        --trial)
            log_info "Initiating CyberSecurity Analyst PRO 14-Day Free Trial..."
            echo -e "\n\033[1;33m======================================================================\033[0m"
            echo -e "         \033[1;32m🛡️  CyberSecurity Analyst PRO - 14-Day Free Trial  🛡️\033[0m"
            echo -e "\033[1;33m======================================================================\033[0m"
            echo -e "Unlock the Go-compiled master daemon, visual Terminal UI, Slack/Telegram"
            echo -e "alerts, and 1-click active firewall blocking."
            echo -e "No commitments. Cancel anytime during the trial. Stripe handles secure billing.\n"
            echo -e "\033[1;36mSecure Stripe Trial Link:\033[0m https://buy.stripe.com/00wdRa3mqesC9Z0gWG0co03"
            echo -e "\033[1;33m======================================================================\033[0m\n"
            
            # Attempt to open browser if xdg-open/open is available
            if command -v xdg-open &>/dev/null; then
                xdg-open "https://buy.stripe.com/00wdRa3mqesC9Z0gWG0co03" &>/dev/null
                log_info "Opening Stripe Secure Checkout in your default browser..."
            elif command -v open &>/dev/null; then
                open "https://buy.stripe.com/00wdRa3mqesC9Z0gWG0co03" &>/dev/null
                log_info "Opening Stripe Secure Checkout in your default browser..."
            else
                log_info "Please copy-paste the secure Stripe Link above to start your trial."
            fi
            
            echo -e "\nAfter starting your trial, you will receive your PRO License Key via email."
            echo -e "Activate your node instantly with:"
            echo -e "  \033[1;32mcsa --activate <YOUR_LICENSE_KEY>\033[0m\n"
            exit 0
            ;;
        --activate|--upgrade) 
            if [ -z "$2" ]; then
                log_error "Error: --activate requires a <LICENSE_KEY>"
                exit 1
            fi
            LICENSE_KEY="$2"
            log_info "Upgrade initiated. Contacting Powerhouse Distribution Server..."
            curl -s "https://ptr.powerhouseconsulting.group/api/dist/install.sh" | sudo bash -s -- --key "$LICENSE_KEY"
            exit 0
            ;;
        *) log_error "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ "$INTERACTIVE" -eq 1 ]; then
    display_header
    load_config
    check_dependencies
    interactive_menu
else
    load_config
    check_dependencies
    parse_logs
    if analyze_with_ai; then
        process_remediation
        handle_output
    fi
fi

fi
