#!/bin/bash

GO_VERSION="1.22.6"
GETH_TARGET_VERSION=v0.9.3
STORY_TARGET_VERSION=v0.10.1
CHAINDATA_DIR="$HOME/.story/geth/iliad/geth/chaindata"
STORY_HOME="$HOME/.story/story"
MONIKER="bh-story-node"


# Check if the OS is Ubuntu
os_check() {
    if [[ "$(uname -a)" != *"Ubuntu"* ]]; then
        echo “Only Ubuntu is supported.”
        exit 1
    fi
}

# Function to update and install packages
install_packages() {
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt-get install -y sudo curl git make build-essential jq wget liblz4-tool aria2
}

# Function to set file handle limits
set_file_limits() {
    ulimit -n 655350
    sudo tee -a /etc/security/limits.conf > /dev/null << EOF
*               soft   nofile          655350
*               hard   nofile          655350
EOF
}

# Function to install or update Go
install_go() {
    local GO_INSTALLED=$(command -v go)
    if [ -z "$GO_INSTALLED" ] || [ "$($GO_INSTALLED version | awk '{print $3}' | sed 's/go//')" \< "$GO_VERSION" ]; then
        echo "Installing or updating Go to version $GO_VERSION..."
        cd $HOME
        sudo rm -rf /usr/local/go
        wget --prefer-family=ipv4 https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
        tar -xvf go${GO_VERSION}.linux-amd64.tar.gz
        sudo mv go /usr/local
        mkdir -p $HOME/goApps/bin
    else
        echo "Go version $GO_VERSION or higher is already installed."
    fi
}

# Function to set Go environment variables
setup_go_env() {
    cat << 'EOF' >> $HOME/.bashrc
export GOROOT=/usr/local/go
export GOPATH=$HOME/goApps
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
EOF
    source $HOME/.bashrc
}

# Function to disable IPv6
disable_ipv6() {
    sudo sed -i -e "s/IPV6=.*/IPV6=no/" /etc/default/ufw
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1
    sudo tee -a /etc/sysctl.conf > /dev/null << EOF
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF
}

# Function to install or update geth
install_geth() {
    local INSTALLED_GETH_VERSION=$(get_geth_version)
    if [ "$INSTALLED_GETH_VERSION" = "none" ] || [ "$INSTALLED_GETH_VERSION" \< "$GETH_TARGET_VERSION" ]; then
        echo "Installing or updating geth to version $GETH_TARGET_VERSION..."
        cd $HOME
        git clone https://github.com/piplabs/story-geth.git
        cd story-geth && git fetch --tags
        git checkout refs/tags/$GETH_TARGET_VERSION
        make geth
        cp $HOME/story-geth/build/bin/geth $HOME/goApps/bin/
    else
        echo "Geth version $INSTALLED_GETH_VERSION is up-to-date."
    fi
}

# Function to get installed geth version
get_geth_version() {
    if [ -f "$HOME/goApps/bin/geth" ]; then
        $HOME/goApps/bin/geth version | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+"
    else
        echo "none"
    fi
}

# Function to create systemd service for geth
create_geth_service() {
    if [ ! -f /etc/systemd/system/geth.service ]; then
        echo "Creating geth.service..."
        sudo tee /etc/systemd/system/geth.service > /dev/null << EOF
[Unit]
Description=geth daemon
After=network-online.target

[Service]
User=ubuntu
ExecStart=$HOME/goApps/bin/geth --iliad --syncmode full
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    fi
}

# Function to create systemd service for story
create_story_service() {
    if [ ! -f /etc/systemd/system/story.service ]; then
        echo "Creating story.service..."
        sudo tee /etc/systemd/system/story.service > /dev/null << EOF
[Unit]
Description=story daemon
After=network-online.target

[Service]
User=ubuntu
WorkingDirectory=$HOME/.story/story
ExecStart=$HOME/goApps/bin/story run
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    fi
}


# Function to check and initialize chaindata
initialize_chaindata() {
    if [ ! -d "$CHAINDATA_DIR" ]; then
        echo "Starting geth to create chaindata directory..."
        sudo systemctl start geth

        for i in {1..20}; do
            if [ -d "$CHAINDATA_DIR" ]; then
                echo "Chaindata directory created."
                sudo systemctl stop geth
                break
            fi
            sleep 1
        done

        if [ ! -d "$CHAINDATA_DIR" ]; then
            echo "Chaindata directory not created after 20 seconds."
        fi
    fi
}

# Function to install or update story client
install_story() {
    local INSTALLED_STORY_VERSION=$(get_story_version)
    if [ "$INSTALLED_STORY_VERSION" = "none" ] || [ "$INSTALLED_STORY_VERSION" \< "$STORY_TARGET_VERSION" ]; then
        echo "Installing or updating story to version $STORY_TARGET_VERSION..."
        cd $HOME
        git clone https://github.com/piplabs/story.git || cd story && git fetch
        git checkout $STORY_TARGET_VERSION
        $(which go) build -o story ./client
        cp $HOME/story/story $HOME/goApps/bin/
        $HOME/goApps/bin/story init --network iliad
        sed -i "s|moniker = \".*\"|moniker = \"${MONIKER}\"|g" $STORY_HOME/config/config.toml
    else
        echo "Story version $INSTALLED_STORY_VERSION is up-to-date."
    fi
}

# Function to get installed story version
get_story_version() {
    if [ -f "$HOME/goApps/bin/story" ]; then
        $HOME/goApps/bin/story version | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+"
    else
        echo "none"
    fi
}

# Function to download and extract data
download_and_extract() {
    local url=$1
    local output_file=$2
    local extract_dir=$3

    echo "Downloading $output_file from $url..."
    wget -O $output_file $url
    if [ -f "$output_file" ]; then
        echo "Extracting $output_file..."
        lz4 -dc $output_file | tar -xvf - -C $extract_dir
        rm $output_file
        echo "Extraction completed."
    else
        echo "Failed to download $output_file."
        exit 1
    fi
}

# Main script starts here
os_check
install_packages
set_file_limits
install_go
setup_go_env
disable_ipv6
install_geth
create_geth_service
create_story_service
initialize_chaindata
install_story


# Download geth and story data
download_and_extract "https://snapshots.bharvest.dev/archive/geth_archive.tar.lz4" "$HOME/gethdata.tar.lz4" "$CHAINDATA_DIR"
download_and_extract "https://snapshots.bharvest.dev/testnet/story/story_1311024.tar.lz4" "$HOME/storydata.tar.lz4" "$STORY_HOME/data"

# Add aliases for geth and story to .bashrc
cat << EOF >> $HOME/.bashrc
alias gstart='sudo systemctl start geth'
alias gstop='sudo systemctl stop geth'
alias istart='sudo systemctl start story'
alias istop='sudo systemctl stop story'
EOF

source $HOME/.bashrc

# Start services
sudo systemctl start geth
sudo systemctl start story

echo "Installation and setup complete."