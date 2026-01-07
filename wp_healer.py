import os
import re
import json
import time
import subprocess
import requests

# --- CONFIGURATION ---
# Add your monitor-specific keys here.
MONITOR_KEYS = [
    "m800973137-f9acea5117e3f75a00b2da85", # guruhospitality.com
    "m802085430-6742a781afbe4b8506b66593", # digi.travel
    "m802085426-622db77c796d61320bf34db2", # publicworkscomplianceadvisors.com
    "m802085402-f9f031dc63d50c246f5475c5", # powerhouseconsulting.group
    "m800973147-324d6126be3b82bfdf17c4f9", # elgrecothailand.com
    "m798678766-c2504abfb5cefd9ec2de74ff", # healthy-skin.me
    "m798678759-0d36092e044ebe39faa818ef", # arttoartgallery.com
    "m798678753-9b172c862f8337e7a7702db8", # ddha.eu
    "m798678747-8476e62bcee1ab7388bb0287", # brusselsbarbell.com
    "m798672501-cbef3d91fa131d9d15719682", # convercon.com
    "m798314069-727465c26244c302a9e9505c", # traveldailynews.com
    "m798314180-790b3368cce27c15be442c5b", # traveldailynews.asia
    "m798314190-b8727ce5d73fadf998dfbffc", # traveldailynews.gr
    "m798678743-c7422a060025da3934e7251c", # zerowaterthailand.com
    "m798678737-919a75eeb198d6c88b735720", # barbellclub.net
    "m798678754-d1404b80688d84e64d1a174f", # thevasilis.com
]

# GEMINI_API_KEY = "..." # Removed in favor of Vertex AI
NOTIFY_EMAIL = "alex@powerhouseconsulting.group"

def run_shell(command):
    """Executes a shell command."""
    try:
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        return result.stdout.strip()
    except Exception as e:
        return str(e)

def get_gcloud_token():
    """Retrieves the gcloud access token."""
    return run_shell("gcloud auth print-access-token")

def get_gcloud_project():
    """Retrieves the gcloud project ID."""
    return run_shell("gcloud config get-value project")

class WPAutoHealer:
    def __init__(self):
        self.session = requests.Session()
        self.project_id = get_gcloud_project()
        # Match the model used in security_analyst/weekly_log_analyst.sh
        self.model_url = f"https://aiplatform.googleapis.com/v1/projects/{self.project_id}/locations/global/publishers/google/models/gemini-3-pro-preview:generateContent"

    def log(self, message):
        print(f"[WP-Healer] {message}")

    def send_email(self, subject, body):
        """Sends an email notification using the system mail command."""
        self.log(f"Sending email notification to {NOTIFY_EMAIL}...")
        try:
            # Escaping single quotes for the shell command
            safe_body = body.replace("'", "'\\''")
            command = f"echo '{safe_body}' | mail -s '{subject}' {NOTIFY_EMAIL}"
            run_shell(command)
        except Exception as e:
            self.log(f"Failed to send email: {e}")

    def get_down_monitors(self):
        """Polls UptimeRobot for sites with status 9 (Down) using multiple keys."""
        down_monitors = []
        url = "https://api.uptimerobot.com/v2/getMonitors"
        
        for key in MONITOR_KEYS:
            payload = {
                "api_key": key,
                "statuses": "9",  # 9 = Down
                "format": "json"
            }
            try:
                response = self.session.post(url, data=payload)
                data = response.json()
                
                if data.get('stat') == 'ok':
                    monitors = data.get('monitors', [])
                    for m in monitors:
                        self.log(f"ALERT: {m['friendly_name']} ({m['url']}) is DOWN.")
                        down_monitors.append(m)
                else:
                    # Ignore errors for specific keys (maybe wrong key or rate limit)
                    self.log(f"API Error for key {key[:5]}...: {data.get('error', {}).get('message')}")
            
            except Exception as e:
                self.log(f"Connection Error for key {key}: {e}")
        
        return down_monitors

    def find_web_root(self, domain):
        """Finds the web root by checking Nginx vhosts."""
        # Clean domain (remove http/www)
        clean_domain = domain.replace("https://", "").replace("http://", "").replace("www.", "").split('/')[0]
        
        # Try to find the conf file
        conf_path = f"/etc/nginx/conf.d/vhosts/{clean_domain}.conf"
        if not os.path.exists(conf_path):
             # Try SSL version
            conf_path = f"/etc/nginx/conf.d/vhosts/{clean_domain}.ssl.conf"
            
        if not os.path.exists(conf_path):
            self.log(f"Could not find config for {clean_domain}")
            return None

        # Grep for root
        with open(conf_path, 'r') as f:
            content = f.read()
            match = re.search(r'root\s+([^;]+);', content)
            if match:
                return match.group(1).strip()
        return None

    def enable_debug(self, web_root, enable=True):
        """Enables or Disables WP_DEBUG in wp-config.php."""
        config_path = os.path.join(web_root, "wp-config.php")
        if not os.path.exists(config_path):
            return False

        with open(config_path, 'r') as f:
            content = f.read()

        if enable:
            # Check if already enabled to avoid double edit
            if "define( 'WP_DEBUG', true );" in content:
                return True
                
            new_content = re.sub(
                r"define\s*\(\s*['\"]WP_DEBUG['\"]\s*,\s*false\s*\);",
                "define( 'WP_DEBUG', true );\ndefine( 'WP_DEBUG_LOG', true );\ndefine( 'WP_DEBUG_DISPLAY', false );",
                content
            )
        else:
             new_content = re.sub(
                r"define\s*\(\s*['\"]WP_DEBUG['\"]\s*,\s*true\s*\);.*?define\s*\(\s*['\"]WP_DEBUG_DISPLAY['\"]\s*,\s*false\s*\);",
                "define( 'WP_DEBUG', false );",
                content,
                flags=re.DOTALL
            )
        
        with open(config_path, 'w') as f:
            f.write(new_content)
        return True

    def get_error_log(self, web_root):
        """Reads the last 30 lines of debug.log."""
        log_path = os.path.join(web_root, "wp-content/debug.log")
        if os.path.exists(log_path):
            return run_shell(f"tail -n 30 {log_path}")
        return None

    def ask_gemini(self, error_log, web_root):
        """Sends the error log to Gemini for analysis."""
        prompt = f"""
        You are a WordPress Expert.
        The website at {web_root} has a Critical Fatal Error.
        Here is the tail of the debug.log:

        {error_log}

        Task: Identify the specific file path and plugin/theme name causing the crash.
        
        CRITICAL RULES:
        1. If the error is in a PLUGIN, recommend disabling it. Set "action": "rename_plugin_folder".
        2. If the error is in a THEME's 'functions.php' file, recommend fixing it. Set "action": "fix_theme_functions".
        3. If the error is in any other theme file or WordPress Core, DO NOT touch it. Return "action": "none".
        
        Output: valid JSON ONLY with this structure:
        {{
            "culprit_name": "folder-name",
            "culprit_file_path": "/full/path/to/file.php",
            "action": "rename_plugin_folder" OR "fix_theme_functions" OR "none",
            "reason": "Brief explanation"
        }}
        """
        
        payload = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}]}
        
        token = get_gcloud_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        try:
            response = self.session.post(self.model_url, json=payload, headers=headers)
            result = response.json()
            if 'error' in result:
                self.log(f"Gemini API Error: {result['error']}")
                return None
                
            # Extract text from response
            text_response = result['candidates'][0]['content']['parts'][0]['text']
            # Clean JSON (remove markdown code blocks)
            clean_json = text_response.replace("```json", "").replace("```", "").strip()
            return json.loads(clean_json)
        except Exception as e:
            self.log(f"Gemini Processing Error: {e}")
            return None

    def get_fixed_code(self, file_content, error_log):
        """Asks Gemini to fix the broken code."""
        prompt = f"""
        You are a PHP Expert.
        The following WordPress functions.php file caused a Fatal Error.
        
        ERROR LOG:
        {error_log}
        
        BROKEN FILE CONTENT:
        ```php
        {file_content}
        ```
        
        Task: Fix the code to resolve the error. 
        Rules:
        1. Return ONLY the full, valid PHP code. 
        2. Do not wrap in markdown (no ```php).
        3. Maintain the original logic as much as possible, only fixing the fatal error.
        """
        
        payload = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}]}
        
        token = get_gcloud_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        try:
            response = self.session.post(self.model_url, json=payload, headers=headers)
            result = response.json()
            if 'error' in result:
                self.log(f"Gemini API Error: {result['error']}")
                return None
            
            text_response = result['candidates'][0]['content']['parts'][0]['text']
            return text_response.replace("```php", "").replace("```", "").strip()
        except Exception as e:
            self.log(f"Gemini Fix Error: {e}")
            return None

    def execute_fix(self, analysis, web_root):
        """Executes the fix proposed by Gemini with STRICT SAFEGUARDS."""
        if not analysis:
            return False

        action = analysis.get('action')
        culprit_name = analysis.get('culprit_name') or analysis.get('culprit_plugin_name')
        file_path = analysis.get('culprit_file_path')
        
        # --- CASE 1: RENAME PLUGIN ---
        if action == 'rename_plugin_folder':
            # 1. INPUT SANITIZATION (Prevent Path Traversal)
            if not culprit_name or '/' in culprit_name or '\\' in culprit_name or '..' in culprit_name:
                self.log(f"Safeguard: Invalid plugin name '{culprit_name}'.")
                return False

            # 2. PATH CONFINEMENT
            plugins_dir = os.path.join(web_root, "wp-content/plugins")
            target_path = os.path.join(plugins_dir, culprit_name)
            
            try:
                real_plugins_dir = os.path.realpath(plugins_dir)
                real_target_path = os.path.realpath(target_path)
            except Exception:
                 self.log("Safeguard: Path resolution failed.")
                 return False
            
            if not real_target_path.startswith(real_plugins_dir):
                self.log(f"Safeguard: Target path {real_target_path} escapes the plugins directory.")
                return False
                
            if not os.path.exists(real_target_path):
                self.log(f"Safeguard: Target {culprit_name} does not exist.")
                return False

            # 3. NON-DESTRUCTIVE BACKUP
            timestamp = int(time.time())
            backup_path = f"{target_path}.disabled.{timestamp}"
            
            try:
                run_shell(f"mv {target_path} {backup_path}")
                self.log(f"SAFE FIX: Renamed {culprit_name} to {os.path.basename(backup_path)}")
                return True
            except Exception as e:
                self.log(f"Safeguard: File operation failed: {e}")
                return False

        # --- CASE 2: FIX THEME FUNCTIONS ---
        elif action == 'fix_theme_functions':
            if not file_path:
                self.log("Safeguard: No file path provided for theme fix.")
                return False
                
            # 1. PATH VALIDATION (Strictly themes/NAME/functions.php)
            themes_dir = os.path.join(web_root, "wp-content/themes")
            try:
                real_themes_dir = os.path.realpath(themes_dir)
                real_file_path = os.path.realpath(file_path)
            except Exception:
                self.log("Safeguard: Path resolution failed.")
                return False
                
            if not real_file_path.startswith(real_themes_dir):
                self.log(f"Safeguard: File {real_file_path} is not in the themes directory.")
                return False
                
            if os.path.basename(real_file_path) != "functions.php":
                self.log(f"Safeguard: Target file {os.path.basename(real_file_path)} is not functions.php.")
                return False
            
            if not os.path.exists(real_file_path):
                self.log(f"Safeguard: File {real_file_path} does not exist.")
                return False

            # 2. BACKUP (Clone)
            timestamp = int(time.time())
            backup_path = f"{real_file_path}.bak.{timestamp}"
            try:
                run_shell(f"cp {real_file_path} {backup_path}")
                self.log(f"Backup created: {backup_path}")
            except Exception as e:
                self.log(f"Safeguard: Backup failed: {e}")
                return False

            # 3. GET FIX
            try:
                with open(real_file_path, 'r') as f:
                    content = f.read()
                
                # We need the error log again. 
                # Optimization: Pass it or retrieve it again? 
                # Since we are inside execute_fix, we don't have the raw log easily unless we passed it.
                # But 'get_error_log' is cheap.
                error_log = self.get_error_log(web_root)
                if not error_log:
                    self.log("Could not retrieve error log for fixing.")
                    return False
                
                fixed_code = self.get_fixed_code(content, error_log)
                if not fixed_code:
                    self.log("Gemini failed to generate a fix.")
                    return False
                
                # 4. WRITE FIX
                with open(real_file_path, 'w') as f:
                    f.write(fixed_code)
                
                self.log(f"SAFE FIX: Patched {real_file_path}")
                return True
                
            except Exception as e:
                self.log(f"Safeguard: File fix failed: {e}")
                return False
                
        else:
            self.log(f"Safeguard: Action '{action}' is not allowed.")
            return False

    def run(self):
        self.log("Starting Health Check...")
        monitors = self.get_down_monitors()
        if not monitors:
            self.log("All monitored sites are UP.")
            return

        for monitor in monitors:
            url = monitor['url']
            self.log(f"Investigating {url}...")
            
            web_root = self.find_web_root(url)
            if not web_root:
                continue
            
            self.log(f"Mapped {url} -> {web_root}")
            
            # 1. Enable Debug
            self.enable_debug(web_root, True)
            
            # 2. Trigger Error
            run_shell(f"curl -I {url}")
            time.sleep(1) # Wait for log write
            
            # 3. Read Log
            log_content = self.get_error_log(web_root)
            if not log_content:
                self.log("No debug.log found.")
                self.enable_debug(web_root, False)
                continue
                
            # 4. Analyze
            self.log("Sending log to Gemini...")
            analysis = self.ask_gemini(log_content, web_root)
            self.log(f"Gemini Analysis: {analysis}")
            
            # 5. Fix
            if analysis:
                fixed = self.execute_fix(analysis, web_root)
                if fixed:
                    # Verify
                    time.sleep(3)
                    check = run_shell(f"curl -I {url}")
                    if "200 OK" in check:
                        self.log(f"SUCCESS! {url} restored.")
                        self.send_email(
                            f"SUCCESS: WP Healer Restored {url}",
                            f"WP Healer detected {url} was down, analyzed the error, and fixed it.\n\nAnalysis: {json.dumps(analysis, indent=2)}\n\nThe site is now returning 200 OK."
                        )
                    else:
                        self.log(f"Fix applied but {url} still returning error.")
                        self.send_email(
                            f"FAILURE: WP Healer attempted fix for {url}",
                            f"WP Healer detected {url} was down and attempted a fix, but the site is still returning an error.\n\nAnalysis: {json.dumps(analysis, indent=2)}\n\nPlease investigate manually."
                        )
                else:
                    self.log(f"No fix could be executed for {url}.")
                    if analysis.get('action') != 'none':
                         self.send_email(
                            f"ALERT: WP Healer Investigation for {url}",
                            f"WP Healer investigated {url} but could not automatically execute the recommended fix.\n\nAnalysis: {json.dumps(analysis, indent=2)}"
                        )
            
            # 6. Cleanup
            self.enable_debug(web_root, False)

if __name__ == "__main__":
    healer = WPAutoHealer()
    healer.run()