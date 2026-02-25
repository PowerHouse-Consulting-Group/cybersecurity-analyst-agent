# Installation & Deployment Guide

This guide outlines the manual installation and configuration of the AI Cybersecurity Log Analyst.

⚠️ **WARNING:** This script requires advanced Linux administration skills. Misconfiguring the log paths or executing an auto-generated remediation script without reviewing it could lock legitimate users out of your server.

## 1. Prerequisites
- **OS**: RHEL/CentOS/AlmaLinux 8+ or Ubuntu 20.04+
- **Packages**: `curl`, `jq`, `mailx`, `nice`, `ionice`
- **Security**: Root privileges (`sudo` or logged in as `root`)
- **API**: A valid Google Cloud Project ID with Vertex AI enabled and a Service Account JSON key.

## 2. Download the Agent
Clone the repository to a secure administration directory (e.g., `/opt/ai-soc/` or `/root/server_scripts/`):
```bash
git clone https://github.com/PowerHouse-Consulting-Group/cybersecurity-analyst-agent.git /opt/ai-soc/
cd /opt/ai-soc/
chmod +x cybersecurity_analyst.sh
```

## 3. Configure the Environment
Copy the configuration template and edit it with your specific server details:
```bash
cp .env.example .env
nano .env
```
Ensure you accurately map the log directories. If you are using a control panel like cPanel, your Apache logs might be located at `/usr/local/apache/domlogs/`.

## 4. Run an Interactive Diagnostic
Before scheduling the script to run automatically, test it using Interactive Mode. This ensures your IAM permissions are correct and the logs are parsing correctly:
```bash
./cybersecurity_analyst.sh --interactive
```
The script will output the Gemini AI report to your terminal and ask if you wish to execute the auto-generated remediation script.

## 5. Setup Automation (Cron)
Once validated, schedule the script to run weekly (or daily, depending on traffic volume) via cron:
```bash
crontab -e
```
Add the following line to run the analysis every Monday at 03:00 AM server time:
```text
0 3 * * 1 /opt/ai-soc/cybersecurity_analyst.sh > /dev/null 2>&1
```

---

> 🏢 **Enterprise Deployments & SLA Operations**
> Configuring IAM roles, mapping complex log directories, and tuning noise filters for High-Traffic environments is not trivial.
> 
> Let **PowerHouse Consulting** deploy this architecture for you. We provide uncompromising infrastructure security backed by a 99.99% uptime guarantee.
> 👉 **[Explore Managed Deployments](https://powerhouseconsulting.group/infrastructure-security)**

---

## License & Ownership

**IP License holder and point of contact:**

**PowerHouse Consulting Group Pte Ltd**  
160 Robinson Road  
SBF Center Unit #24-09,  
068914, Singapore  
ACRA UEN 202108925N  

📧 **Contact:** support (at) powerhouseconsulting.group