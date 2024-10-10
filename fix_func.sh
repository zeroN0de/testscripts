#!/bin/bash

# Check if the OS is Ubuntu
os_check() {
    if [[ "$(uname -a)" != *"Ubuntu"* ]]; then
        echo "Ubuntu만 지원합니다."
        exit 1
    fi
}