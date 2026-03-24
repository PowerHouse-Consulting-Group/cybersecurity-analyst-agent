<div align="center">
  <img src="https://placehold.co/800x200/222222/D4AF37.png?text=PowerHouse+Consulting:+Securing+the+Core" alt="Securing the Core: Infrastructure & Threat Mitigation" width="100%">
  <h1>🛡️ Autonomous AI Cybersecurity Log Analyst</h1>
  <p><b>An AI-Driven Security Operations Center (SOC) for Enterprise Linux Servers. Powered by Multiple LLMs (Gemini, OpenAI, Claude, Local).</b></p>
  <p>
    <a href="https://powerhouseconsulting.group/infrastructure-security"><b>Learn about our Enterprise WAF & Server Hardening Deployments 🚀</b></a>
  </p>
</div>

---

## 🛑 The Vulnerability (The Pain)
Unpatched CMS platforms, open ports, fragile shared-hosting setups, and zero bot-filtering lead to data breaches, resource exhaustion, and catastrophic crashes during traffic spikes.

This script acts as your first line of defense, proactively analyzing chaotic server logs to identify backdoors, malicious scrapers, and automated threat vectors before they compromise your data sovereignty.

## 🏰 The Fortress Architecture (The Solution)
The **AI Cybersecurity Log Analyst** uses your choice of LLM to digest thousands of lines of chaotic Apache, Nginx, Mail, System (`journalctl`), and Database (MySQL/MariaDB) logs, distilling them into a high-signal intelligence report.

It then generates **executable, precise firewall (CSF) and remediation scripts** to neutralize the threats instantly.

### Multi-LLM & Local Privacy Support
We believe in absolute data privacy. You can route your log analysis through:
- **Google Gemini** (Vertex AI)
- **OpenAI** (GPT-4o)
- **Anthropic Claude** (3.5 Sonnet)
- **xAI** (Grok)
- **Local / Air-Gapped LLMs** (Ollama, LM Studio) - *Keep 100% of your logs on your local network!*

---

## 🚀 Installation & Configuration

### Prerequisites & Potential Failure Scenarios
Before installing, ensure your system meets the following requirements. The script may break or fail silently if these are missing:
- **`jq` and `curl`:** Essential for parsing JSON and making API requests. The script will fail without them. (Install via `sudo apt install jq curl` or `sudo dnf install jq curl`).
- **Mail Transfer Agent (MTA):** If you plan to run the script via Cron and receive email reports, your server must have a working MTA providing `/usr/sbin/sendmail` (e.g., Postfix, Exim). Without this, Cron reports will fail to send.
- **For Google Gemini Users:** The script authenticates using `gcloud auth print-access-token`. You MUST have the Google Cloud CLI (`gcloud`) installed and authenticated (e.g., via `gcloud auth login` or a service account) on your server. If using OpenAI, Claude, or Local LLMs, this is not required.

### Option A: Universal Installer (Recommended)
```bash
curl -sL https://raw.githubusercontent.com/PowerHouse-Consulting-Group/cybersecurity-analyst-agent/main/install.sh | sudo bash
```

### Option B: Package Managers (.deb / .rpm)
Download the latest release from the [Releases page](../../releases):
**Ubuntu/Debian:** `sudo dpkg -i ai-cybersecurity-analyst_*.deb`
**CentOS/AlmaLinux/RHEL:** `sudo rpm -i ai-cybersecurity-analyst_*.rpm`

### Configuration
After installation, configure your environment variables:
```bash
nano /opt/ai-soc/.env
```
Select your `LLM_PROVIDER` and enter the corresponding API key.

### Running the Agent
Run interactively:
```bash
sudo /opt/ai-soc/cybersecurity_analyst.sh --interactive
```
Or schedule via Cron:
```bash
0 3 * * 1 /opt/ai-soc/cybersecurity_analyst.sh > /dev/null 2>&1
```

---

## 💎 Upgrade to CyberSecurity Analyst PRO

While the Community Version provides essential log analysis, our **PRO Version** is designed for Enterprise Defense, offering a real-time Terminal UI (TUI) Dashboard and active remediation capabilities.

**PRO Features Include:**
*   **[I] AI Threat Insight & OSINT:** Auto-enrich attacker IPs via Shodan & AbuseIPDB for deep context.
*   **[T] Blast Radius Timeline:** Cross-correlate Nginx, Auth, and DB logs 5 mins before/after breaches to build an incident timeline.
*   **[D] Active Deception & Tarpits:** Route attackers to endlessh honeypots instead of just dropping packets.
*   **[R] MITRE ATT&CK Reporting:** Generate 1-click executive PDF/JSON reports for SOC2, PCI-DSS, and ISO27001 audits.
*   **[S] Global Fleet Defense:** Sync firewall blocks across your entire server cluster instantly.

👉 **[GET PRO TODAY: PowerHouse Consulting Security](https://powerhouseconsulting.group/infrastructure-security/)**

---

## ❓ FAQ
**Q: Do my logs get sent to your servers?**
A: No. The script runs entirely on your infrastructure and communicates directly with the LLM provider you configure (or your local Ollama instance).

**Q: Does it automatically block IPs?**
A: No. It generates a remediation script and prompts you for confirmation before executing any destructive or blocking commands.

**Q: How do I report a bug or request a feature?**
A: Please use the GitHub Issues tab. We have automated workflows to triage and tag your requests.

---

> ## 🏢 Enterprise Deployments & Managed Security
> Setting up IAM roles, tuning noise filters, configuring firewall logic, and integrating this agent into custom, High-Availability VPS architectures requires absolute precision.
> 
> Let **PowerHouse Consulting** deploy this architecture for you. We provide uncompromising infrastructure security, active bot-mitigation suites, and deep-code security audits backed by a 99.99% uptime guarantee.
> 
> 👉 **[Schedule a Deep-Code Diagnostic & Custom Deployment](https://powerhouseconsulting.group/infrastructure-security)**

---

## ⚖️ Legal & Copyright

**© 2026 PowerHouse Consulting Group Pte Ltd. All Rights Reserved.**

This software is the intellectual property of PowerHouse Consulting Group Pte Ltd. It is provided under the terms of the included LICENSE file. 

**IP License holder and point of contact:**
PowerHouse Consulting Group Pte Ltd
160 Robinson Road
SBF Center Unit #24-09,
Singapore 068914
ACRA UEN: 202108925N
Contact Email: support(at)powerhouseconsulting.group