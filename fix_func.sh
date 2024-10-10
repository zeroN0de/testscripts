#!/bin/bash

# Check if the OS is Ubuntu
os_check() {
    if [[ "$(uname -a)" != *"Ubuntu"* ]]; then
        echo “Only Ubuntu is supported.”
        exit 1
    fi
}
os_check
