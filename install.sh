#!/bin/bash

set -e

# This script sets up the necessary tools and applications for ServerSide Client 
# Apps to connect to the ServerSide Main App from a Raspberry Pi

echo "Updating package list..."
sudo apt-get update

echo "Upgrading installed packages..."
sudo apt-get upgrade -y

echo "Install JQ"
sudo apt-get install jq -y

echo "Installing expect..."
sudo apt-get install expect -y

# Create the expect script to set the VNC password
cat << EOF > set_vnc_password.exp
#!/usr/bin/expect
spawn vncpasswd
expect "Password:"
send "Santana@\r"
expect "Verify:"
send "Santana@\r"
expect "Would you like to enter a view-only password (y/n)?"
send "n\r"
expect eof
EOF

# Make the expect script executable
chmod +x set_vnc_password.exp

echo "Installing TightVNCServer..."
sudo apt-get install tightvncserver -y

# Now run the expect script
./set_vnc_password.exp

echo "Starting TightVNCServer..."
tightvncserver :1


# Configure TightVNCServer to start on boot
(crontab -l 2>/dev/null; echo "@reboot tightvncserver :1") | crontab -

echo "Installing Wireguard..."
sudo apt install wireguard -y

echo "Installing resolvconf..."
sudo apt-get install resolvconf -y

echo "Enabling and starting resolvconf service..."
sudo systemctl enable resolvconf
sudo systemctl start resolvconf

# Check for existing WireGuard keys
if [ ! -f ~/privatekey ] || [ ! -f ~/publickey ]; then
    echo "Generating WireGuard keys..."
    wg genkey | tee ~/privatekey | wg pubkey > ~/publickey
else
    echo "WireGuard keys already exist, using existing keys..."
fi

# Read the public key into a variable
WG_PUBLIC_KEY=$(cat ~/privatekey | wg pubkey)

# Check if WireGuard configuration already exists
if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo "Fetching IP address from the server and configuring WireGuard..."

    # Send the public key in JSON format to your server and store the response
    RESPONSE=$(curl -X POST -H "Content-Type: application/json" -d "{\"public_key\": \"$WG_PUBLIC_KEY\"}" http://68.190.110.57:44111/get_ip)

    # Extract the IP address from the JSON response
    IP_ADDRESS=$(echo $RESPONSE | jq -r '.ip_address')

    # Configure WireGuard with the obtained IP address
    echo -e "[Interface]\nAddress = $IP_ADDRESS/32\nPrivateKey = $(cat ~/privatekey)\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = TTj19WgC9WWze9VfeOzo3fqsktZISF39XLoCsH7MFgc=\nEndpoint = 68.190.110.57:44112\nAllowedIPs = 10.0.0.1/32\nPersistentKeepalive = 25" | sudo tee /etc/wireguard/wg0.conf

    # Set correct permissions for the WireGuard configuration file
    sudo chmod 600 /etc/wireguard/wg0.conf

    # Enable and start WireGuard
    sudo systemctl enable wg-quick@wg0
    sudo systemctl start wg-quick@wg0

else
    echo "WireGuard is already configured."
fi

# Enable SSH
sudo systemctl enable ssh
sudo systemctl start ssh

# Clone the GitHub repository
echo "Cloning the GitHub repository..."
git clone https://github.com/theBullfish/PiInstallStuff.git

# Navigate to the repository directory
cd PiInstallStuff

# Install Python3 venv module
echo "Installing Python3 venv..."
sudo apt-get install python3-venv -y

# Check if the requirements file exists in the 'Pi Browser Collector' directory
if [ -f "Pi Browser Collector/requirements.txt" ]; then
    echo "Setting up Python virtual environment..."

    # Navigate to the 'Pi Browser Collector' directory
    cd "Pi Browser Collector"

    # Create a virtual environment
    python3 -m venv venv

    # Activate the virtual environment
    source venv/bin/activate

    # Install Python dependencies
    echo "Installing Python dependencies..."
    pip install -r requirements.txt

    # Deactivate the virtual environment
    deactivate

    # Create a systemd service file for the Python app
    echo "Creating a systemd service for the Python app..."
    echo -e "[Unit]\nDescription=My Python App\nAfter=network.target\n\n[Service]\nExecStart=$(pwd)/venv/bin/python3 $(pwd)/app.py\nWorkingDirectory=$(pwd)\nRestart=always\nUser=pi\nGroup=pi\nEnvironment=\"PATH=/bin:/usr/local/bin\"\nEnvironment=\"PYTHONUNBUFFERED=1\"\n\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/myapp.service

    # Enable and start the service
    echo "Enabling and starting the systemd service..."
    sudo systemctl enable myapp.service
    sudo systemctl start myapp.service

    # Return to the original directory
    cd ../..
else
    echo "No Python requirements found. Skipping Python setup."
fi


