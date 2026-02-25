# Google Cloud Vertex AI Configuration

This agent uses the `gcloud` CLI to authenticate against Google Cloud and interact with the Vertex AI (Gemini Pro) API endpoints. 

You must securely configure a Service Account (IAM) with the principle of least privilege.

## 1. Create a Service Account
1. Log into your Google Cloud Console.
2. Navigate to **IAM & Admin > Service Accounts**.
3. Click **Create Service Account** (e.g., `ai-soc-agent`).
4. Grant the Service Account the **Vertex AI User** role. This role allows the agent to call the Gemini API without having access to other cloud resources.
5. Create and download a **JSON Key** for this Service Account.

## 2. Secure the JSON Key on the Server
Upload the downloaded `secure-sa-key.json` file to your server. It is critical that this file is locked down.

```bash
mv /path/to/upload/secure-sa-key.json /root/.gcp-backup-key.json
chmod 400 /root/.gcp-backup-key.json
chown root:root /root/.gcp-backup-key.json
```

## 3. Authenticate the CLI
The script relies on `gcloud auth print-access-token` running locally. You must authenticate the `gcloud` utility using the secure JSON key:

```bash
gcloud auth login --cred-file=/root/.gcp-backup-key.json
```

Verify authentication was successful:
```bash
gcloud config set project [YOUR-PROJECT-ID]
gcloud auth list
```

You are now ready to execute `./cybersecurity_analyst.sh`.

---

> 🏢 **Secure Integrations & IAM Configuration**
> Setting up cloud IAM roles, managing JSON keys securely, and configuring network boundaries can introduce severe vulnerabilities if executed incorrectly.
> 
> Let **PowerHouse Consulting** deploy this architecture for you. We provide uncompromising infrastructure security, active bot-mitigation suites, and strict access-control configurations.
> 👉 **[Schedule a Custom Deployment](https://powerhouseconsulting.group/infrastructure-security)**

---

## License & Ownership

**IP License holder and point of contact:**

**PowerHouse Consulting Group Pte Ltd**  
160 Robinson Road  
SBF Center Unit #24-09,  
068914, Singapore  
ACRA UEN 202108925N  

📧 **Contact:** support (at) powerhouseconsulting.group