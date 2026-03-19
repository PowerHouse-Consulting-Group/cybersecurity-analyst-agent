#!/bin/bash
set -e

echo "Installing Autonomous AI Cybersecurity Log Analyst..."

echo "Checking for required dependencies (jq, curl)..."
if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
    echo "Dependencies missing. Attempting to install..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq curl
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq curl
    else
        echo "Error: Package manager not found. Please install 'jq' and 'curl' manually."
        exit 1
    fi
fi

INSTALL_DIR="/opt/ai-soc"
sudo mkdir -p "$INSTALL_DIR"

echo "Downloading latest version..."
sudo curl -sL "https://raw.githubusercontent.com/PowerHouse-Consulting-Group/cybersecurity-analyst-agent/main/cybersecurity_analyst.sh" -o "$INSTALL_DIR/cybersecurity_analyst.sh"
sudo curl -sL "https://raw.githubusercontent.com/PowerHouse-Consulting-Group/cybersecurity-analyst-agent/main/.env.example" -o "$INSTALL_DIR/.env.example"

sudo chmod +x "$INSTALL_DIR/cybersecurity_analyst.sh"

if [ ! -f "$INSTALL_DIR/.env" ]; then
    sudo cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    echo "Created default .env file at $INSTALL_DIR/.env"
fi

echo "Installation complete!"
echo "Please configure your API keys and paths in $INSTALL_DIR/.env"
echo "You can run the script manually: sudo $INSTALL_DIR/cybersecurity_analyst.sh --interactive"
