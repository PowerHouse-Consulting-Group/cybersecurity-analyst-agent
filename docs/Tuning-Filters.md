# Tuning & Noise Reduction Filters

The efficiency of the AI Cybersecurity Analyst—and your Gemini API token consumption—relies heavily on filtering out "benign" log noise before it is sent to the AI for analysis.

If your server receives thousands of requests per second, you must aggressively tune the `NOISE_FILTER` variable located in your `.env` file.

## The `.env` NOISE_FILTER Variable
This variable expects an Extended Regular Expression (regex). The script uses `grep -vE "$NOISE_FILTER"` to ignore any log lines that match the patterns defined here.

### Example Default Filter:
```bash
NOISE_FILTER="favicon\.ico|robots\.txt|apple-touch-icon|AH00124|AH01071|File does not exist: /var/www/html"
```

## Adding Custom Exclusions
To prevent false positives, you should monitor your initial reports. If Gemini consistently highlights a benign warning, add its unique identifier to your filter.

**Common Scenarios to Filter:**
1.  **Missing Assets**: Bots constantly scan for `.env`, `wp-login.php`, or missing fonts. If you already have a WAF blocking these, and you don't care about the 404s, filter them:
    `...|wp-login\.php|wp-config|woff2...`
2.  **Internal Redirects (Apache)**: "AH00124" is a common internal redirect limit error that is often benign config noise.
3.  **Known IP Addresses**: If an internal monitoring tool (like UptimeRobot) occasionally triggers a warning, filter its IP address:
    `...|192\.168\.1\.100|uptime-bot...`

### Important Regex Note:
Remember to escape periods (`\.`) and pipe (`|`) characters correctly if you intend to use them as literals within your regex.

---

> 🏢 **Need Help Tuning for High Traffic?**
> In high-volume environments, tuning the agent requires analyzing server topologies to prevent dropping critical indicators of compromise (IoC). 
> 
> Let **PowerHouse Consulting** handle your Server Hardening & Log Tuning.
> 👉 **[Contact our DevOps Team](https://powerhouseconsulting.group/infrastructure-security)**

---

## License & Ownership

**IP License holder and point of contact:**

**PowerHouse Consulting Group Pte Ltd**  
160 Robinson Road  
SBF Center Unit #24-09,  
068914, Singapore  
ACRA UEN 202108925N  

📧 **Contact:** support (at) powerhouseconsulting.group