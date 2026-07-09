<div align="center">
  <img src="https://placehold.co/800x200/0a0a0a/D4AF37.png?text=PowerHouse+Consulting+Group+%7C+Securing+the+Core" alt="PowerHouse Consulting Group" width="100%">
  <h1>🛡️ CyberSecurity Analyst Agent</h1>
  <p><b>Free Autonomous SOC for Linux Servers. AI-powered log analysis with zero data egress.</b></p>
  <p>
    <a href="https://powerhouseconsulting.group/cybersecurity-analyst/"><b>🌐 Project Homepage</b></a> &nbsp;|&nbsp;
    <a href="https://powerhouseconsulting.group/cybersecurity-analyst/#pricing"><b>💎 Upgrade to PRO</b></a>
  </p>
</div>

---

## What It Does

The CyberSecurity Analyst Agent parses your Apache, Nginx, auth, database, and system logs using AI — and generates executable firewall remediation scripts. Free forever. Zero data leaves your server.

- **Multi-LLM:** Gemini, OpenAI, Claude, xAI, or local Ollama/LM Studio
- **Zero Data Egress:** Built-in PII scrubber redacts IPs and emails before API transmission
- **Firewall Ready:** Generates CSF, UFW, and iptables block lists
- **No registration:** No credit card, no email, no account

---

## 🚀 Quick Install

```bash
curl -fsSL https://powerhouseconsulting.group/cybersecurity-analyst-agent/install.sh | sudo bash
```

Installs in under 30 seconds. Creates `/opt/ai-soc/` and registers the `csa` command system-wide.

---

## 🖥️ TUI Interface

```
===========================================================================
   ______      __                 _____                      _ __
  / ____/_  __/ /_  ___  _____   / ___/___  ________  ______(_) /___  __
 / /   / / / / __ \/ _ \/ ___/   \__ \/ _ \/ ___/ / / / ___/ / __/ / / /
/ /___/ /_/ / /_/ /  __/ /      ___/ /  __/ /__/ /_/ / /  / / /_/ /_/ /
\____/\__, /_.___/\___/_/      /____/\___/\___/\__,_/_/  /_/\__/\__, /
     /____/                                                    /____/
===========================================================================
        AI Cybersecurity Log Analyst - Community Edition v1.1.7

[ SYSTEM MAIN MENU ]
> 1) Start Live Log Scan
   Time ranges: 24h | 3d | 7d | 14d | Current month
> 2) Proactive Hardening Audit
> 3) 🔥 Upgrade to PRO Version (Activate License Key)
> 4) Quit Application
-------------------------------------------------
```

---

## ⚙️ First-Run Setup

On first run, if no `.env` file exists, the script auto-creates one from the template and shows:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚙️  FIRST-TIME SETUP — Configuration Required
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Creating default .env from template...

You MUST configure the following before running scans:
  1. CONFIGURED=true   — Set this to true at the top of the file
  2. YOUR_EMAIL        — Where reports are sent
  3. LLM_PROVIDER      — AI provider (gemini, openai, claude, local)
  4. MODEL_ID          — AI model to use
  5. API Key           — Your provider's API key
  6. Log Paths         — Paths to your server logs

Edit:  nano /opt/ai-soc/.env
Re-run:  csa
```

A persistent warning banner stays visible above the menu until `CONFIGURED=true` is set. The hardening audit, upgrade, and quit options remain functional without configuration.

---

## 📋 Features

### Log Scan (with time-range selection)
```
[ SELECT TIME RANGE ]
> 1) Last 24 hours
> 2) Last 3 days
> 3) Last 7 days
> 4) Last 14 days
> 5) Current month
> 6) Cancel
```

All log sources adapt: `-mtime`, `journalctl --since`, and `DATE_PATTERN` use the selected range. Cross-month ranges are handled automatically.

### Proactive Hardening Audit
Checks SSH config, firewall status, fail2ban, unattended security updates, and open ports with ✓/✗ reporting and issue count.

### Configuration Sentinel
A `CONFIGURED=true` flag in `.env` prevents the app from silently running with default placeholder values. The warning is visible but non-blocking for non-scan operations.

### License Validation
PRO upgrade validation has a 10-second connect timeout + 15-second max duration. Invalid or unreachable servers return a clear error instead of hanging.

---

## 🔒 Supported Log Sources

| Source | Path / Method |
|---|---|
| Apache error logs | `$APACHE_LOG_DIR` (configurable) |
| Nginx error logs | `$NGINX_LOG_DIR` (configurable) |
| System/Firewall logs | `$SYSTEM_LOG_PATH` (e.g., `/var/log/syslog`) |
| Journalctl (systemd) | `journalctl -p 0..3 --since` |
| Mail logs | `$MAIL_LOG_PATH` (e.g., `/var/log/mail.log`) |
| MySQL slow queries | `$MYSQL_SLOW_LOG_PATH` |

---

## 💎 PRO Version

| Feature | Community | PRO |
|---|---|---|
| Core language | Bash | Go-native binary |
| Multi-LLM API | ✓ | ✓ |
| TUI dashboard | ✓ | ✓ (Interactive) |
| Real-time watcher daemon | Cron interval | Real-time |
| Fleet clustering | — | ✓ (Master/Node) |
| 1-click firewall blocking | — | ✓ (CSF/UFW) |
| Slack/Telegram alerts | — | ✓ |
| MITRE ATT&CK mapping | — | ✓ |
| OSINT enrichment (Shodan/AbuseIPDB) | — | ✓ |

**Pricing:** From $497/yr (single node) to $1,497/yr (fleet up to 5 nodes). 14-day free trial.

👉 **[View Pricing & Upgrade](https://powerhouseconsulting.group/cybersecurity-analyst/#pricing)**

---

## 📝 Changelog

### v1.1.7 (2026-07-09)
- Persistent config warning visible above menu (not a blocker)
- Options 2/3/4 functional without .env configuration
- Single-line rejection for scan attempts when unconfigured

### v1.1.6 (2026-07-09)
- Time-range hints visible inline on main menu
- PRO upsell message on exit

### v1.1.5 (2026-07-09)
- `CONFIGURED` sentinel in `.env.example` prevents default-value runs
- Time-range submenu: 24h, 3d, 7d, 14d, Current month
- Dynamic `DATE_PATTERN` computation for cross-month ranges

### v1.1.4 (2026-07-09)
- License validation timeout (10s connect + 15s max)
- Graceful error messages instead of hanging on invalid keys

### v1.1.3 (2026-07-09)
- Real hardening audit replaces fake placeholder
- SSH, firewall, fail2ban, unattended updates, open ports checks

### v1.1.2 (2026-07-09)
- `VERSION` constant and TUI header display

### v1.1.1 (2026-07-09)
- Purchase URLs fixed to `cybersecurity-analyst/#pricing`
- `install.sh` moved to dedicated directory
- First-run `.env` guided setup experience

### v1.1.0 (2026-06-17)
- `csa` global command wrapper
- Multi-LLM API bindings (Gemini, OpenAI, Claude, xAI, Ollama)

---

## ⚖️ Legal

**© 2026 PowerHouse Consulting Group Pte Ltd. All Rights Reserved.**

PowerHouse Consulting Group Pte Ltd  
160 Robinson Road, SBF Center Unit #24-09  
Singapore 068914 | ACRA UEN: 202108925N  
support@powerhouseconsulting.group