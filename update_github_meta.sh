#!/bin/bash

# This script helps apply the SEO-optimized metadata and tags to your GitHub repository
# You must have the GitHub CLI (gh) installed and authenticated.

REPO_NAME="powerhouseconsulting/ai-cybersecurity-log-analyzer" # <-- Update this to your actual GitHub Repo

echo "Applying SEO Tags and Meta Description to GitHub Repository..."

# 1. Update the Repository Description and Homepage URL
gh repo edit "$REPO_NAME" 
  --description "An Autonomous, AI-Driven Security Operations Center (SOC) for Enterprise Linux Servers. Uses Google Gemini to analyze logs and generate auto-remediation scripts." 
  --homepage "https://powerhouseconsulting.group/infrastructure-security"

# 2. Apply High-Volume SEO Topics (Tags)
gh repo edit "$REPO_NAME" 
  --add-topic "cybersecurity" 
  --add-topic "ai-agent" 
  --add-topic "gemini-api" 
  --add-topic "devops" 
  --add-topic "server-hardening" 
  --add-topic "bot-mitigation" 
  --add-topic "bash-script" 
  --add-topic "log-analysis" 
  --add-topic "ciso" 
  --add-topic "soc"

echo "Repository metadata successfully updated for maximum SEO reach."
