#!/bin/bash

# Update system and install required packages
apt-get update -y && apt-get upgrade -y && apt-get install sudo curl -y
sudo apt-get install -y git curl make build-essential jq wget liblz4-tool aria2

# Increase file handle limits
ulimit -n 655350

# Set system-wide file handle limits
cat << EOF | sudo tee -a /etc/security/limits.conf
*               soft   nofile          655350
*               hard   nofile          655350
EOF

# Install Go
GO_INSTALLED=$(command -v go)
GO_VERSION="1.22.2"

if [ -z "$GO_INSTALLED" ]; then
    echo "Go is not installed. Installing Go version $GO_VERSION..."
elif [ "$($GO_INSTALLED version | awk '{print $3}' | sed 's/go//')" \< "$GO_VERSION" ]; then
    echo "Installed Go version is less than $GO_VERSION. Upgrading Go..."
else
    echo "Go version $GO_VERSION or higher is already installed."
fi

# Install Go if not installed or if version is lower than 1.22.2
if [ -z "$GO_INSTALLED" ] || [ "$($GO_INSTALLED version | awk '{print $3}' | sed 's/go//')" \< "$GO_VERSION" ]; then
    cd $HOME
    sudo rm -rf /usr/local/go
    wget --prefer-family=ipv4 https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
    tar -xvf go${GO_VERSION}.linux-amd64.tar.gz
    sudo mv go /usr/local
    /usr/local/go/bin/go version
    which /usr/local/go/bin/go
    mkdir -p $HOME/goApps/bin
else
    echo "Go is already installed and up-to-date."
fi

# Add Go environment variables to .bashrc
export GOROOT=/usr/local/go
export GOPATH=$HOME/goApps
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

cat << 'EOF' >> $HOME/.bashrc
export GOROOT=/usr/local/go
export GOPATH=$HOME/goApps
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
EOF

source $HOME/.bashrc

# Disable IPv6
sudo sed -i -e "s/IPV6=.*/IPV6=no/" /etc/default/ufw
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

cat << EOF | sudo tee -a /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

# Install Execution Client (story-geth)
GETH_TARGET_VERSION="v0.9.3"

# Function to get the installed geth version (if installed)
get_geth_version() {
    if [ -f "$HOME/goApps/bin/geth" ]; then
        INSTALLED_VERSION=$($HOME/goApps/bin/geth version | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
        echo $INSTALLED_VERSION
    else
        echo "none"
    fi
}

# Check the installed geth version
INSTALLED_GETH_VERSION=$(get_geth_version)

# If no geth is installed or the version is lower than 0.9.3, install/upgrade geth
if [ "$INSTALLED_GETH_VERSION" = "none" ]; then
    echo "geth is not installed. Installing geth version $GETH_TARGET_VERSION..."
    cd $HOME
    git clone https://github.com/piplabs/story-geth.git
    cd story-geth
    git checkout $GETH_TARGET_VERSION
    make geth
    cp $HOME/story-geth/build/bin/geth $HOME/goApps/bin/
    $HOME/goApps/bin/geth version
elif [ "$INSTALLED_GETH_VERSION" \< "$GETH_TARGET_VERSION" ]; then
    echo "Installed geth version is lower than $GETH_TARGET_VERSION. Upgrading to version $GETH_TARGET_VERSION..."
    cd $HOME/story-geth
    git fetch
    git checkout $GETH_TARGET_VERSION
    make geth
    cp $HOME/story-geth/build/bin/geth $HOME/goApps/bin
    $HOME/goApps/bin/geth version
else
    echo "geth version $INSTALLED_GETH_VERSION is already installed and up-to-date."
fi

# Check if geth.service already exists, if not, create it
if [ -f /etc/systemd/system/geth.service ]; then
    echo "geth.service file already exists. Skipping creation."
else
    echo "Creating geth.service file..."
    cat << EOF | sudo tee /etc/systemd/system/geth.service
[Unit]
Description=geth daemon
After=network-online.target

[Service]
User=ubuntu
ExecStart=$HOME/goApps/bin/geth --iliad --syncmode full
KillMode=process
KillSignal=SIGINT
TimeoutStopSec=90
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "geth.service file created."
fi

# Story-geth init step (for chaindata)
CHAINDATA_DIR="$HOME/.story/geth/iliad/geth/chaindata"

# Starting geth, if not exist DIR Chaindata.
if [ ! -d "$CHAINDATA_DIR" ]; then
    echo “chaindata directory does not exist, start geth service...”
    sudo systemctl start geth

    # Check if the chaindata directory is created for up to 20 seconds
    for i in {1..20}; do
        if [ -d "$CHAINDATA_DIR" ]; then
            echo “The chaindata directory has been created.”
            break
        fi
        sleep 1
    done

    # Once the Chaindata directory has been created, stop the geth service
    if [ -d "$CHAINDATA_DIR" ]; then
        echo “Stopping the geth service...”
        sudo systemctl stop geth
    else
        echo “The chaindata directory was not created in 20 seconds.”
    fi
else
    echo “The chaindata directory already exists.”
fi
# Install Consensus Client (iliad)
# Define the target story version
STORY_TARGET_VERSION="v0.10.2"

# Function to get the installed story version (if installed)
get_story_version() {
    if [ -f "$HOME/goApps/bin/story" ]; then
        INSTALLED_VERSION=$($HOME/goApps/bin/story version | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
        echo $INSTALLED_VERSION
    else
        echo "none"
    fi
}

# Check the installed story version
INSTALLED_STORY_VERSION=$(get_story_version)

# If no story is installed or the version is lower than 0.10.1, install/upgrade story
if [ "$INSTALLED_STORY_VERSION" = "none" ]; then
    echo "story is not installed. Installing story version $STORY_TARGET_VERSION..."
    cd $HOME
    git clone https://github.com/piplabs/story.git
    cd story
    git checkout $STORY_TARGET_VERSION
    $(which go) build -o story ./client
    cp $HOME/story/story $HOME/goApps/bin/
    $HOME/goApps/bin/story version
elif [ "$INSTALLED_STORY_VERSION" \< "$STORY_TARGET_VERSION" ]; then
    echo "Installed story version is lower than $STORY_TARGET_VERSION. Upgrading to version $STORY_TARGET_VERSION..."
    cd $HOME/story
    git fetch
    git checkout $STORY_TARGET_VERSION
    $(which go) build -o story ./client
    cp $HOME/story/story $HOME/goApps/bin/
    $HOME/goApps/bin/story version
else
    echo "story version $INSTALLED_STORY_VERSION is already installed and up-to-date."
fi

# Copy story binary to goApps bin directory
cp $HOME/story/story $HOME/goApps/bin/

# Initialize story client and modify configuration files
$HOME/goApps/bin/story init --network iliad

# Modify story.toml
STORY_HOME=$HOME/.story/story
sed -i "s/snapshot-interval = .*/snapshot-interval = 0/" $STORY_HOME/config/story.toml

# Modify config.toml
MONIKER=bh-story-node
sed -i "s|moniker = \".*\"|moniker = \"${MONIKER}\"|g" $STORY_HOME/config/config.toml


# Download gethdata.tar.lz4 from the provided URL
echo "Downloading gethdata.tar.lz4..."
wget -O $HOME/gethdata.tar.lz4 https://snapshots.bharvest.dev/archive/geth_archive.tar.lz4

# Verify the download
if [ -f "$HOME/gethdata.tar.lz4" ]; then
    echo "Download completed successfully."
else
    echo "Error: Failed to download the file."
    exit 1
fi

# Extract the downloaded tar.lz4 archive
echo "Extracting gethdata.tar.lz4..."
lz4 -dc $HOME/gethdata.tar.lz4 | tar -xvf - -C $HOME/.story/geth/iliad/geth/chaindata

# Verify the extraction
if [ "$(ls -A $HOME/.story/geth/iliad/geth/chaindata)" ]; then
    echo "Extraction completed successfully."
else
    echo "Error: Extraction failed or chaindata directory is empty."
    exit 1
fi

# Clean up the downloaded archive file
rm $HOME/gethdata.tar.lz4

echo "gethdata.tar.lz4 downloaded, extracted, and placed in $HOME/.story/geth/iliad/geth/chaindata."

# Download storydata.tar.lz4 from the provided URL
echo "Downloading storydata.tar.lz4..."
wget -O $HOME/storydata.tar.lz4 https://snapshots.bharvest.dev/archive/story_archive.tar.lz4

# Verify the download
if [ -f "$HOME/storydata.tar.lz4" ]; then
    echo "Download completed successfully."
else
    echo "Error: Failed to download the file."
    exit 1
fi

# Extract the downloaded tar.lz4 archive
echo "Extracting storydata.tar.lz4..."
lz4 -dc $HOME/storydata.tar.lz4 | tar -xvf - -C $HOME/.story/story/data

# Verify the extraction
if [ "$(ls -A $HOME/.story/story/data)" ]; then
    echo "Extraction completed successfully."
else
    echo "Error: Extraction failed or data directory is empty."
    exit 1
fi

# Clean up the downloaded archive file
rm $HOME/storydata.tar.lz4

echo "storydata.tar.lz4 downloaded, extracted, and placed in $HOME/.story/story/data."



# Check if the story.service file already exists
if [ -f /etc/systemd/system/story.service ]; then
    echo "story.service file already exists. Skipping creation."
else
    echo "Creating story.service file..."
    cat << EOF | sudo tee /etc/systemd/system/story.service
[Unit]
Description=story daemon
After=network-online.target

[Service]
User=ubuntu
WorkingDirectory=$HOME/.story/story
ExecStart=$HOME/goApps/bin/story run
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=beacon
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "story.service file created."
fi

# Reload systemd and enable services
sudo systemctl daemon-reload

# Add aliases for geth and iliad to .bashrc
cat << EOF >> $HOME/.bashrc
alias gstart='sudo systemctl start geth'
alias gstop='sudo systemctl stop geth'
alias gstatus='sudo systemctl status geth'
alias glog='journalctl -u geth -f -o cat'

alias istart='sudo systemctl start story'
alias istop='sudo systemctl stop story'
alias istatus='sudo systemctl status story'
alias ilog='journalctl -u story -f -o cat'
alias ist='curl localhost:26657/status | jq'
EOF
echo "Write a alias for geth.service and story.service"

# Reload bashrc
source $HOME/.bashrc

# Start services
sudo systemctl start geth
echo "Starting geth.service"

sudo systemctl start story
echo "Starting story.service"

echo "Installation and setup complete."
