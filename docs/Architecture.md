# The Fortress Architecture: AI Log Analyst

The **Autonomous AI Cybersecurity Log Analyst** acts as a lightweight, read-only daemon on your Linux servers. Instead of running heavy agents that consume resources, this script leverages built-in Linux utilities to stream pre-filtered log data to Google's Gemini AI for deep-code and behavioral analysis.

## Core Data Flow

1.  **Ingestion & Aggregation**: The script uses `find`, `grep`, and `nice` (to ensure low I/O priority) to scan local web and system logs (Apache, Nginx, `/var/log/syslog`, `/var/log/maillog`) for critical threat keywords (`error`, `denied`, `crashed`).
2.  **Noise Reduction**: A robust regex filter (`NOISE_FILTER`) strips out benign events (e.g., missing `favicon.ico` or basic 404s).
3.  **Truncation**: To optimize for API token limits and prevent payload injection, massive log entries are truncated to `MAX_LINE_LENGTH` (default: 500 characters).
4.  **AI Intelligence (Gemini Pro)**: The aggregated, high-signal data is structured into JSON and sent securely to Google Cloud Vertex AI via REST API.
5.  **Remediation Generation**: Gemini analyzes the behavioral patterns and outputs a detailed Markdown report and a purely executable Bash script containing `csf` (ConfigServer Security & Firewall) blocking commands.
6.  **Action/Notification**: 
    - In **Interactive Mode**, the IT administrator is prompted via CLI to review and execute the remediation script immediately.
    - In **Cron Mode**, the Markdown report and script location are emailed securely to the configured CISO/IT Operations team.

## High-Availability Integration

While this agent is highly capable as a standalone tool, it performs best when integrated into **High-Availability VPS Architectures** featuring upstream edge caching and Enterprise Web Application Firewalls (WAFs) like Cloudflare.

The Analyst agent monitors the "origin" server, catching sophisticated threats that bypass the edge layer (e.g., Application-level exploits, malicious PHP uploads, brute-force SSH attempts).

---

> 🏢 **Require a Custom Integration?**
> Integrating this SOC agent into custom architectures requires precision tuning. Let **PowerHouse Consulting** deploy this for you securely.
> 👉 **[Schedule a Deep-Code Diagnostic & Custom Deployment](https://powerhouseconsulting.group/infrastructure-security)**

---

## License & Ownership

**IP License holder and point of contact:**

**PowerHouse Consulting Group Pte Ltd**  
160 Robinson Road  
SBF Center Unit #24-09,  
068914, Singapore  
ACRA UEN 202108925N  

📧 **Contact:** support (at) powerhouseconsulting.group

## 🛡️ Security Safeguards & Zero Trust Automation

This agent is built with **Zero Trust Automation** principles to ensure it cannot compromise your server's integrity:
- **Explicit Permission Mandate:** The AI operates as an advisory tool. It proposes remediations as purely executable Bash scripts that *require* a human System Administrator's explicit confirmation before execution.
- **Database Protection:** The AI is strictly forbidden from executing raw database queries or modifications (MySQL, MariaDB, PostgreSQL). All DB-related fixes are provided as manual text instructions.
- **Core System Integrity:** The AI is restricted from proposing modifications to core OS files (e.g., `/etc/passwd`, `/etc/sudoers`) and blocked from using destructive commands (`rm -rf`, `truncate`).
- **Safe Network Abstraction:** The agent relies on safe firewall wrappers (`csf`, `ufw`) and will never execute raw `iptables --flush` commands that could sever administrative access.
