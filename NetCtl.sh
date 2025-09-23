#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
GOLD='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directory and files for storing data
TOKEN_DIR="$HOME/.NetCtl"
TOKEN_FILE="$TOKEN_DIR/.token"
CONNECTIONS_DIR="$TOKEN_DIR/connections"
CONNECTIONS_LOG="$TOKEN_DIR/connections.log"

create_completion_script() {
    local completion_dir="$HOME/.bash_completion.d"
    local completion_file="$completion_dir/netctl-completion.bash"

    # Only proceed if completion file doesn't exist
    if [ ! -f "$completion_file" ]; then
        # Create completion directory if it doesn't exist
        mkdir -p "$completion_dir"

        # Create the completion script
        cat > "$completion_file" << 'EOF'
_netctl_complete() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="token login tcp http list stop stopall help"

    case "$prev" in
        "stop")
            if [ -d "$HOME/.NetCtl/connections" ] && [ "$(ls -A "$HOME/.NetCtl/connections" 2>/dev/null)" ]; then
                local active_ids=""
                while IFS= read -r f; do
                    if [ -f "$f" ]; then
                        local pid
                        pid=$(jq -r '.pid' "$f" 2>/dev/null)
                        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                            active_ids+=" $(basename "$f" .json)"
                        fi
                    fi
                done < <(find "$HOME/.NetCtl/connections" -name "*.json" 2>/dev/null)
                COMPREPLY=( $(compgen -W "$active_ids" -- "$cur") )
            fi
            ;;
        "tcp")
            local ports="80 443 3000 3306 5432 8000 8080 8443 9000"
            COMPREPLY=( $(compgen -W "$ports -s" -- "$cur") )
            ;;
        "http")
            local ports="80 443 3000 3306 5432 8000 8080 8443 9000"
            COMPREPLY=( $(compgen -W "$ports -c" -- "$cur") )
            ;;
        "-s"|"--service")
            # Service name completion
            COMPREPLY=()
            ;;
        "-c"|"--custom_domain")
            # Domain completion
            COMPREPLY=()
            ;;
        *)
            COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
            ;;
    esac
    return 0
}

complete -F _netctl_complete NetCtl
complete -F _netctl_complete ./NetCtl
EOF

        # Make it executable
        chmod +x "$completion_file"

        # Add sourcing to bashrc only if not already there
        if ! grep -q "bash_completion.d/netctl-completion.bash" "$HOME/.bashrc"; then
            {
              echo ""
              echo "# NetCtl completion"
              echo "if [ -f \"$completion_file\" ]; then"
              echo "    source \"$completion_file\""
              echo "fi"
            } >> "$HOME/.bashrc"
            # shellcheck disable=SC1090
            source "$HOME/.bashrc"
        fi
    fi
}

# Function to detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS=$NAME
        if command -v apt-get >/dev/null 2>&1; then
            PKG_MANAGER="apt-get"
            INSTALL_CMD="apt-get install -y"
        elif command -v yum >/dev/null 2>&1; then
            PKG_MANAGER="yum"
            INSTALL_CMD="yum install -y"
        elif command -v dnf >/dev/null 2>&1; then
            PKG_MANAGER="dnf"
            INSTALL_CMD="dnf install -y"
        elif command -v apk >/dev/null 2>&1; then
            PKG_MANAGER="apk"
            INSTALL_CMD="apk add --no-cache"
        else
            echo -e "${RED}Error: Unsupported package manager${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Could not detect operating system${NC}"
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    local deps=("$@")
    local to_install=()

    detect_os

    # Check which dependencies need to be installed
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            case $dep in
                sshpass) to_install+=("sshpass") ;;
                jq)      to_install+=("jq") ;;
                curl)    to_install+=("curl") ;;
                qrencode) to_install+=("qrencode") ;;
                ssh)
                    if [ "$PKG_MANAGER" = "apt-get" ]; then
                        to_install+=("openssh-client")
                    else
                        to_install+=("openssh")
                    fi
                    ;;
            esac
        fi
    done

    # If there are packages to install
    if [ ${#to_install[@]} -ne 0 ]; then
        echo -e "${YELLOW}Missing required packages: ${to_install[*]}${NC}"

        # Check if we have sudo access
        if ! command -v sudo >/dev/null 2>&1; then
            if [ "$EUID" -ne 0 ]; then
                echo -e "${RED}Error: This script needs root access to install required packages${NC}"
                exit 1
            fi
            $INSTALL_CMD "${to_install[@]}"
        else
            echo -e "${CYAN}Installing required packages...${NC}"
            sudo $INSTALL_CMD "${to_install[@]}"
        fi

        # Verify installation
        for dep in "${to_install[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                echo -e "${RED}Error: Failed to install $dep${NC}"
                exit 1
            fi
        done

        echo -e "${GREEN}Successfully installed required packages${NC}"
    fi
}

# Function to check internet connectivity
check_internet() {
    if ! curl -s --connect-timeout 5 https://api.netctl.net >/dev/null; then
        echo -e "${RED}Error: No internet connection or API is unreachable${NC}"
        return 1
    fi
    return 0
}

# Function to check dependencies (simplified - all required)
check_dependencies() {
    local required_deps=("jq" "sshpass" "curl" "ssh" "qrencode")
    install_dependencies "${required_deps[@]}"
    create_completion_script
}

# Function to check if token exists
check_token_exists() {
    if [ ! -f "$TOKEN_FILE" ]; then
        echo -e "${RED}Error: Token not found. Please save a token first.${NC}"
        exit 1
    fi
}

# Function to display help
show_help() {
   echo -e "${CYAN}Usage:${NC}"
   echo -e "  $(basename "$0") ${GREEN}token${NC} <token>                         - Save the token"
   echo -e "  $(basename "$0") ${GREEN}login${NC}                                 - Login via browser to get token"
   echo -e "  $(basename "$0") ${GREEN}tcp${NC} <[host:]port> [-s <service>]      - Run TCP tunneling (with optional service name)"
   echo -e "  $(basename "$0") ${GREEN}http${NC} <[host:]port> [-c <domain>]      - Run HTTP tunneling"
   echo -e "  $(basename "$0") ${GREEN}list${NC}                                  - List active connections"
   echo -e "  $(basename "$0") ${GREEN}stop${NC} <id>                             - Stop a specific connection"
   echo -e "  $(basename "$0") ${GREEN}stopall${NC}                               - Stop all connections"
   echo -e "  $(basename "$0") ${GREEN}help${NC}                                  - Show this help message"
}

# Function to save token
save_token() {
    mkdir -p "$TOKEN_DIR"
    echo "$1" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    mkdir -p "$CONNECTIONS_DIR"
    echo -e "${GREEN}Token saved successfully.${NC}"
}

# Function to handle browser login flow with QR code
browser_login() {
    local hub_base="https://hub.netctl.net"
    local uuid_str
    uuid_str=$(cat /proc/sys/kernel/random/uuid)
    local login_url="${hub_base}/login?uuid=${uuid_str}"
    local poll_interval=2
    local timeout_minutes=5
    local start_time
    start_time=$(date +%s)
    local timeout_seconds=$((timeout_minutes * 60))

    echo -e "${CYAN}Initiating browser login...${NC}"
    echo -e ""
    echo -e "${PURPLE}UUID: ${GOLD}${uuid_str}${NC}"
    echo -e ""
    
    # Generate and display QR code
    echo -e "${CYAN}Scan this QR code to login:${NC}"
    echo -e ""
    qrencode -t UTF8 "$login_url" 2>/dev/null || {
        echo -e "${YELLOW}QR code generation failed, using URL instead.${NC}"
    }
    echo -e ""
    echo -e "${PURPLE}Or open this URL manually:${NC}"
    echo -e "${CYAN}${login_url}${NC}"
    echo -e ""
    echo -e "${PURPLE}Waiting for login to complete (up to ${timeout_minutes} minutes)...${NC}"

    # Start polling for token
    while true; do
        local current_time elapsed response login_status token
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout_seconds ]; then
            echo -e ""
            echo -e "${RED}Login timed out after ${timeout_minutes} minutes. Please try again.${NC}"
            return 1
        fi

        response=$(curl -s --connect-timeout 10 "${hub_base}/api/check-login/${uuid_str}")

        if [ $? -eq 0 ]; then
            login_status=$(echo "$response" | jq -r '.login // false')

            if [ "$login_status" = "true" ]; then
                token=$(echo "$response" | jq -r '.connectionToken // empty')

                if [ -n "$token" ] && [ "$token" != "null" ]; then
                    echo -e ""
                    echo -e "${GREEN}Login successful!${NC}"
                    save_token "$token"
                    return 0
                fi
            fi
        fi

        sleep $poll_interval
    done
}

# Function to handle API response
handle_api_response() {
    local response=$1
    local status

    if ! status=$(echo "$response" | jq -r '.status' 2>/dev/null); then
        echo -e "${RED}Error: Invalid API response format${NC}" >&2
        return 1
    fi

    if [ "$status" = "error" ]; then
        local error_code error_message
        error_code=$(echo "$response" | jq -r '.error.code' 2>/dev/null)
        error_message=$(echo "$response" | jq -r '.error.message' 2>/dev/null)

        case $error_code in
            401) echo -e "${RED}Error: Invalid token. Please get a new token from the dashboard.${NC}" >&2 ;;
            403) echo -e "${RED}Error: $error_message${NC}" >&2 ;;
            404) echo -e "${RED}Error: Domain not found or inactive.${NC}" >&2 ;;
            503) echo -e "${RED}Error: Service temporarily unavailable. Please try again later.${NC}" >&2 ;;
            *)   echo -e "${RED}Error: Unknown error occurred - $error_message${NC}" >&2 ;;
        esac
        return 1
    fi

    return 0
}

# Function to make API request
get_connection_details() {
    local connection_type=$1
    local custom_domain=$2
    local service_name=$3
    local token
    token=$(cat "$TOKEN_FILE")

    local request_data
    if [ -n "$custom_domain" ] && [ -n "$service_name" ]; then
        request_data="{\"Token\":\"$token\", \"Connection-Type\":\"$connection_type\", \"domain\":\"$custom_domain\", \"service_name\":\"$service_name\"}"
    elif [ -n "$custom_domain" ]; then
        request_data="{\"Token\":\"$token\", \"Connection-Type\":\"$connection_type\", \"domain\":\"$custom_domain\"}"
    elif [ -n "$service_name" ]; then
        request_data="{\"Token\":\"$token\", \"Connection-Type\":\"$connection_type\", \"service_name\":\"$service_name\"}"
    else
        request_data="{\"Token\":\"$token\", \"Connection-Type\":\"$connection_type\"}"
    fi

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        "https://api.netctl.net/connect-user")

    [ -z "$response" ] && { echo -e "${RED}Error: Empty API response${NC}" >&2; return 1; }
    echo "$response" | jq . >/dev/null 2>&1 || { echo -e "${RED}Error: Invalid JSON response: '$response'${NC}" >&2; return 1; }

    # Check for error codes in the response
    local error_code
    error_code=$(echo "$response" | jq -r '.error.code // empty')
    if [ -n "$error_code" ]; then
        handle_api_response "$response"
        return 1
    fi

    # Prevent duplicate remote port in-use with a live PID
    if handle_api_response "$response"; then
        local remote_port in_use=false
        remote_port=$(echo "$response" | jq -r '.data.port')

        for conn_file in "$CONNECTIONS_DIR"/*.json; do
            if [ -f "$conn_file" ]; then
                local existing_remote_port existing_pid
                existing_remote_port=$(jq -r '.remote_port' "$conn_file")
                existing_pid=$(jq -r '.pid' "$conn_file")
                if [ "$existing_remote_port" = "$remote_port" ] && is_process_running "$existing_pid"; then
                    in_use=true
                    break
                fi
            fi
        done

        if [ "$in_use" = false ]; then
            echo "$response"
            return 0
        fi
    fi

    echo -e "${RED}Error:${NC} ${CYAN}Rapid request error.${NC}" >&2
    return 1
}

# Function to generate unique connection ID
generate_connection_id() {
    printf "%05d" $((RANDOM % 100000))
}

# Function to check if service name is already in use
check_service_conflict() {
    local service_name=$1
    
    if [ ! -d "$CONNECTIONS_DIR" ]; then
        return 0  # No conflicts if no connections directory
    fi
    
    for conn_file in "$CONNECTIONS_DIR"/*.json; do
        [ -f "$conn_file" ] || continue
        
        local existing_service_name
        existing_service_name=$(jq -r '.service_name // empty' "$conn_file" 2>/dev/null)
        
        if [ "$existing_service_name" = "$service_name" ]; then
            local conn_id status
            conn_id=$(jq -r '.id' "$conn_file")
            status=$(jq -r '.status // "active"' "$conn_file")
            
            case "$status" in
                "active"|"reconnecting")
                    echo -e "${RED}Error: Service '$service_name' already exists (Connection ID: $conn_id, Status: $status)${NC}"
                    echo -e "${YELLOW}Use './NetCtl stop $conn_id' to stop the existing connection first.${NC}"
                    return 1
                    ;;
                "failed")
                    # Remove failed service and allow new connection
                    rm -f "$conn_file"
                    return 0
                    ;;
            esac
        fi
    done
    
    return 0  # No conflict found
}

# Improved auto-watcher function for service connections
start_auto_watcher() {
    local conn_id=$1
    local service_name=$2
    local local_host=$3
    local local_port=$4
    local token=$5
    
    (
        local check_interval=15  # Check more frequently
        local max_failures=10   # More attempts
        local failure_count=0
        local conn_file="$CONNECTIONS_DIR/$conn_id.json"
        
        sleep 5  # Short initial delay
        
        while [ -f "$conn_file" ] && [ $failure_count -lt $max_failures ]; do
            local current_pid
            current_pid=$(jq -r '.pid // empty' "$conn_file" 2>/dev/null)
            
            # Check if SSH process is dead
            if [ -n "$current_pid" ] && ! kill -0 "$current_pid" 2>/dev/null; then
                # Mark as reconnecting
                local temp_file
                temp_file=$(mktemp)
                jq '.status = "reconnecting"' "$conn_file" > "$temp_file" && mv "$temp_file" "$conn_file"
                
                # Connection died, attempt reconnect
                local request_data="{\"Token\":\"$token\", \"Connection-Type\":\"tcp\", \"service_name\":\"$service_name\"}"
                local response
                response=$(curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -d "$request_data" \
                    "https://api.netctl.net/connect-user" 2>/dev/null)
                
                if [ $? -eq 0 ] && echo "$response" | jq -e '.data' >/dev/null 2>&1; then
                    local new_endpoint new_hostname new_remote_port
                    new_endpoint=$(echo "$response" | jq -r '.data.endpoint')
                    new_hostname=$(echo "$response" | jq -r '.data.hostname')
                    new_remote_port=$(echo "$response" | jq -r '.data.port')
                    
                    # Start new SSH connection
                    local username password
                    username=$(echo "$token" | base64 --decode | cut -d: -f1)
                    password=$(echo "$token" | base64 --decode | cut -d: -f2)
                    
                    export SSHPASS="$password"
                    sshpass -e ssh -p 8522 \
                        -o StrictHostKeyChecking=no \
                        -o ExitOnForwardFailure=yes \
                        -o ServerAliveCountMax=3 \
                        -o ConnectTimeout=15 \
                        "$username@$new_endpoint" \
                        -N -R "0.0.0.0:$new_remote_port:$local_host:$local_port" \
                        >/dev/null 2>&1 &
                    
                    local new_pid=$!
                    unset SSHPASS
                    
                    sleep 3
                    
                    if kill -0 "$new_pid" 2>/dev/null; then
                        # Update connection file with new details
                        temp_file=$(mktemp)
                        jq --arg pid "$new_pid" \
                           --arg endpoint "$new_endpoint" \
                           --arg hostname "$new_hostname" \
                           --arg port "$new_remote_port" \
                           --arg reconnected "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                           '.pid = ($pid | tonumber) | .hostname = $hostname | .remote_port = ($port | tonumber) | .reconnected_at = $reconnected | .status = "active"' \
                           "$conn_file" > "$temp_file" && mv "$temp_file" "$conn_file"
                        
                        failure_count=0  # Reset failure count on success
                    else
                        failure_count=$((failure_count + 1))
                        sleep 5
                    fi
                else
                    failure_count=$((failure_count + 1))
                    sleep 5
                fi
            fi
            
            sleep $check_interval
        done
        
        # If we exit the loop due to max failures, mark as failed
        if [ $failure_count -ge $max_failures ] && [ -f "$conn_file" ]; then
            temp_file=$(mktemp)
            jq '.status = "failed" | .auto_reconnect = false' "$conn_file" > "$temp_file" && mv "$temp_file" "$conn_file"
        fi
    ) &
    
    # Save watcher PID to connection file
    local watcher_pid=$!
    local temp_file
    temp_file=$(mktemp)
    jq --arg wpid "$watcher_pid" '.watcher_pid = ($wpid | tonumber)' "$CONNECTIONS_DIR/$conn_id.json" > "$temp_file" && mv "$temp_file" "$CONNECTIONS_DIR/$conn_id.json"
}

# Function to stop watcher when connection is stopped
stop_auto_watcher() {
    local conn_file=$1
    local watcher_pid
    watcher_pid=$(jq -r '.watcher_pid // empty' "$conn_file" 2>/dev/null)
    
    if [ -n "$watcher_pid" ] && kill -0 "$watcher_pid" 2>/dev/null; then
        kill "$watcher_pid" 2>/dev/null
    fi
}

# Function to save connection details
save_connection_details() {
    local conn_id=$1
    local conn_type=$2
    local local_host=$3
    local local_port=$4
    local remote_port=$5
    local hostname=$6
    local pid=$7
    local custom_domain=$8
    local endpoint=$9
    local service_name=${10}

    mkdir -p "$CONNECTIONS_DIR"
    
    if [ -n "$custom_domain" ] && [ -n "$service_name" ]; then
        cat > "$CONNECTIONS_DIR/$conn_id.json" << EOF
{
    "id": "$conn_id",
    "type": "$conn_type",
    "local_host": "$local_host",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "hostname": "$hostname",
    "CNAME": "$endpoint",
    "custom_domain": "$custom_domain",
    "service_name": "$service_name",
    "pid": $pid,
    "auto_reconnect": true,
    "status": "active",
    "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    elif [ -n "$custom_domain" ]; then
        cat > "$CONNECTIONS_DIR/$conn_id.json" << EOF
{
    "id": "$conn_id",
    "type": "$conn_type",
    "local_host": "$local_host",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "hostname": "$hostname",
    "CNAME": "$endpoint",
    "custom_domain": "$custom_domain",
    "pid": $pid,
    "status": "active",
    "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    elif [ -n "$service_name" ]; then
        cat > "$CONNECTIONS_DIR/$conn_id.json" << EOF
{
    "id": "$conn_id",
    "type": "$conn_type",
    "local_host": "$local_host",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "hostname": "$hostname",
    "service_name": "$service_name",
    "pid": $pid,
    "auto_reconnect": true,
    "status": "active",
    "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    else
        cat > "$CONNECTIONS_DIR/$conn_id.json" << EOF
{
    "id": "$conn_id",
    "type": "$conn_type",
    "local_host": "$local_host",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "hostname": "$hostname",
    "pid": $pid,
    "status": "active",
    "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi

    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Started $conn_type tunnel: $conn_id (PID: $pid)" >> "$CONNECTIONS_LOG"
}

# Function to verify port is actually ready
verify_port_ready() {
    local port=$1
    local max_attempts=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if ss -Htln 2>/dev/null | grep -q ":$port\b"; then
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    return 1
}

# Function to check if process is running and stable
is_process_running() {
    local pid=$1
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

# SSH background runner with service name support and auto-watcher
run_ssh_background() {
    local conn_id=$1
    local user_pass=$2
    local local_host=$3
    local local_port=$4
    local endpoint=$5
    local hostname=$6
    local remote_port=$7
    local connection_type=$8
    local custom_domain=$9
    local service_name=${10}
    local max_retries=3
    local retry_delay=3
    local check_delay=2

    local username password
    username=$(echo "$user_pass" | base64 --decode | cut -d: -f1)
    password=$(echo "$user_pass" | base64 --decode | cut -d: -f2)

    export SSHPASS="$password"

    # Retry loop for SSH connection
    for ((i=1; i<=max_retries; i++)); do
        if (( i == 1 )); then
           echo -e "${CYAN}Initial connection attempt...${NC}"
        else
           echo -e "${CYAN}Retrying connection... (attempt $i of $max_retries)${NC}"
        fi

        sshpass -e ssh -p 8522 \
            -o StrictHostKeyChecking=no \
            -o ExitOnForwardFailure=yes \
            -o ServerAliveCountMax=3 \
            -o ConnectTimeout=15 \
            "$username@$endpoint" \
            -N -R "$([[ $connection_type == tcp ]] && echo "0.0.0.0:" || echo "")$remote_port:$local_host:$local_port" \
            >/dev/null 2>&1 &

        local pid=$!
        unset SSHPASS

        sleep $check_delay

        if is_process_running "$pid"; then
            sleep $check_delay
            if is_process_running "$pid"; then
                save_connection_details "$conn_id" "$connection_type" "$local_host" "$local_port" "$remote_port" "$hostname" "$pid" "$custom_domain" "$endpoint" "$service_name"

                # Start auto-watcher for service connections
                if [ -n "$service_name" ]; then
                    start_auto_watcher "$conn_id" "$service_name" "$local_host" "$local_port" "$user_pass"
                fi

                echo -e "${GREEN}Connection started successfully!${NC}"
                echo -e "${PURPLE}Connection ID: ${GOLD}$conn_id${NC}"
                echo -e "${PURPLE}Type: ${GOLD}${connection_type}${NC}"
                if [ -n "$service_name" ]; then
                    echo -e "${PURPLE}Service: ${GOLD}${service_name}${NC} ${GREEN}(Auto-reconnect enabled)${NC}"
                fi
                echo -e "${PURPLE}Local Host: ${GOLD}${local_host}${NC}"
                echo -e "${PURPLE}Local Port: ${GOLD}${local_port}${NC}"
                if [ -n "$custom_domain" ]; then
                    echo -e "${PURPLE}CNAME: ${CYAN}${endpoint}${NC}"
                    echo -e "${PURPLE}hostname: ${CYAN}${hostname}${NC}"
                    echo -e "${PURPLE}URL: ${CYAN}https://${custom_domain}${NC}"
                else
                    echo -e "${PURPLE}URL: ${CYAN}${hostname}${NC}"
                fi
                echo -e "${PURPLE}Remote Port: ${GOLD}${remote_port}${NC}"
                echo -e "${PURPLE}PID: ${GOLD}${pid}${NC}"
                return 0
            fi
        fi

        echo -e "${YELLOW}Connection attempt $i failed, retrying...${NC}"
        kill $pid 2>/dev/null
        sleep $retry_delay
    done

    echo -e "${RED}Error: Failed to establish SSH connection after $max_retries attempts${NC}"
    return 1
}

# Fixed function to list active connections
list_connections() {
   if [ ! -d "$CONNECTIONS_DIR" ] || [ -z "$(ls -A "$CONNECTIONS_DIR")" ]; then
       echo -e "${GOLD}No active connections.${NC}"
       return
   fi

   echo -e "${CYAN}Active Connections:${NC}"
   echo -e "${PURPLE}----------------------------------------${NC}"

   for conn_file in "$CONNECTIONS_DIR"/*.json; do
       [ -f "$conn_file" ] || continue

       local conn_data conn_id conn_type local_host local_port remote_port hostname CNAME custom_domain service_name auto_reconnect status_field pid started_at status
       conn_data=$(cat "$conn_file")
       conn_id=$(echo "$conn_data" | jq -r '.id')
       conn_type=$(echo "$conn_data" | jq -r '.type')
       local_host=$(echo "$conn_data" | jq -r '.local_host // "127.0.0.1"')
       local_port=$(echo "$conn_data" | jq -r '.local_port')
       remote_port=$(echo "$conn_data" | jq -r '.remote_port')
       hostname=$(echo "$conn_data" | jq -r '.hostname')
       CNAME=$(echo "$conn_data" | jq -r '.CNAME // empty')
       custom_domain=$(echo "$conn_data" | jq -r '.custom_domain // empty')
       service_name=$(echo "$conn_data" | jq -r '.service_name // empty')
       auto_reconnect=$(echo "$conn_data" | jq -r '.auto_reconnect // false')
       status_field=$(echo "$conn_data" | jq -r '.status // "active"')
       pid=$(echo "$conn_data" | jq -r '.pid')
       started_at=$(echo "$conn_data" | jq -r '.started_at')

       if is_process_running "$pid"; then
           status="${GREEN}ACTIVE${NC}"
       else
           # For service connections with auto-reconnect, check status field
           if [ -n "$service_name" ] && [ "$auto_reconnect" = "true" ]; then
               case "$status_field" in
                   "reconnecting") status="${YELLOW}RECONNECTING${NC}" ;;
                   "failed") status="${RED}FAILED${NC}" ;;
                   *) status="${YELLOW}RECONNECTING${NC}" ;;
               esac
           else
               status="${RED}DEAD${NC}"
               # Only clean up non-service connections
               rm -f "$conn_file"
               continue
           fi
       fi

       echo -e "${PURPLE}ID: ${GOLD}$conn_id${NC}"
       echo -e "${PURPLE}Type: ${GOLD}$conn_type${NC}"
       if [ -n "$service_name" ]; then
           if [ "$auto_reconnect" = "true" ]; then
               echo -e "${PURPLE}Service: ${GOLD}$service_name${NC} ${GREEN}(Auto-reconnect)${NC}"
           else
               echo -e "${PURPLE}Service: ${GOLD}$service_name${NC}"
           fi
       fi
       echo -e "${PURPLE}Local Host: ${GOLD}$local_host${NC}"
       echo -e "${PURPLE}Local Port: ${GOLD}$local_port${NC}"
       if [ -n "$custom_domain" ]; then
           echo -e "${PURPLE}CNAME: ${CYAN}${CNAME}${NC}"
           echo -e "${PURPLE}hostname: ${CYAN}${hostname}${NC}"
           echo -e "${PURPLE}URL: ${CYAN}https://${custom_domain}${NC}"
       else
           echo -e "${PURPLE}URL: ${CYAN}${hostname}${NC}"
       fi
       echo -e "${PURPLE}Remote Port: ${GOLD}${remote_port}${NC}"
       echo -e "${PURPLE}Status: $status"
       echo -e "${PURPLE}PID: ${GOLD}${pid}${NC}"
       echo -e "${PURPLE}Started: ${GOLD}$started_at${NC}"
       echo -e "${PURPLE}----------------------------------------${NC}"
   done
}

# Function to stop a specific connection
stop_connection() {
    local conn_id=$1
    local conn_file="$CONNECTIONS_DIR/$conn_id.json"

    if [ ! -f "$conn_file" ]; then
        echo -e "${RED}Error: Connection ID not found.${NC}"
        return 1
    fi

    # Stop auto-watcher if it exists
    stop_auto_watcher "$conn_file"

    local pid
    pid=$(jq -r '.pid' "$conn_file")

    if is_process_running "$pid"; then
        kill "$pid" 2>/dev/null
        sleep 1
        if is_process_running "$pid"; then
            kill -9 "$pid" 2>/dev/null
        fi
        echo -e "${GREEN}Connection $conn_id stopped successfully.${NC}"
    else
        echo -e "${YELLOW}Connection $conn_id was already dead.${NC}"
    fi

    rm -f "$conn_file"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Stopped tunnel: $conn_id (PID: $pid)" >> "$CONNECTIONS_LOG"
}

# Function to stop all connections
stop_all_connections() {
    if [ ! -d "$CONNECTIONS_DIR" ] || [ -z "$(ls -A "$CONNECTIONS_DIR")" ]; then
        echo -e "${GOLD}No active connections to stop.${NC}"
        return
    fi

    local stopped=0
    for conn_file in "$CONNECTIONS_DIR"/*.json; do
        [ -f "$conn_file" ] || continue
        local conn_id
        conn_id=$(basename "$conn_file" .json)
        stop_connection "$conn_id"
        ((stopped++))
    done

    echo -e "${GREEN}Stopped $stopped connection(s).${NC}"
}

# Main script
main() {
    check_dependencies

    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi

    case "$1" in
        token)
            if [ "$#" -ne 2 ]; then
                echo -e "${RED}Error: Token not specified.${NC}"
                show_help
                exit 1
            fi
            save_token "$2"
            ;;
        login)
            check_internet || exit 1
            browser_login
            ;;
        tcp|http)
            local command="$1"
            shift
            local local_host="127.0.0.1"
            local local_port=""
            local custom_domain=""
            local service_name=""

            while [ $# -gt 0 ]; do
                case "$1" in
                    -c|--custom_domain)
                        if [ "$command" != "http" ]; then
                            echo -e "${RED}Error: Custom domain can only be used with HTTP connections${NC}"
                            exit 1
                        fi
                        [ -z "$2" ] && { echo -e "${RED}Error: Missing value for -c/--custom_domain${NC}"; exit 1; }
                        custom_domain="$2"
                        shift 2
                        ;;
                    -s|--service)
                        if [ "$command" != "tcp" ]; then
                            echo -e "${RED}Error: Service name can only be used with TCP connections${NC}"
                            exit 1
                        fi
                        [ -z "$2" ] && { echo -e "${RED}Error: Missing value for -s/--service${NC}"; exit 1; }
                        service_name="$2"
                        shift 2
                        ;;
                    *)
                        if [ -z "$local_port" ]; then
                            # Accept PORT or HOST:PORT
                            if [[ "$1" == *:* ]]; then
                                local_host="${1%%:*}"
                                local_port="${1##*:}"
                            else
                                local_port="$1"
                            fi
                            shift
                        else
                            echo -e "${RED}Error: Unexpected argument '$1'${NC}"
                            show_help
                            exit 1
                        fi
                        ;;
                esac
            done

            if ! [[ "$local_port" =~ ^[1-9][0-9]*$ ]] || [ "$local_port" -gt 65535 ]; then
                echo -e "${RED}Error: Invalid port. Use a number between 1 and 65535.${NC}"
                show_help
                exit 1
            fi

            # Check for service name conflicts before proceeding
            if [ -n "$service_name" ]; then
                check_service_conflict "$service_name" || exit 1
            fi

            check_token_exists
            check_internet || exit 1

            local response endpoint hostname remote_port conn_id token
            response=$(get_connection_details "$command" "$custom_domain" "$service_name") || exit 1

            endpoint=$(echo "$response" | jq -r '.data.endpoint')
            hostname=$(echo "$response" | jq -r '.data.hostname')
            remote_port=$(echo "$response" | jq -r '.data.port')

            conn_id=$(generate_connection_id)
            token=$(cat "$TOKEN_FILE")

            run_ssh_background "$conn_id" "$token" "$local_host" "$local_port" "$endpoint" "$hostname" "$remote_port" "$command" "$custom_domain" "$service_name"
            ;;
        list)
            list_connections
            ;;
        stop)
            if [ "$#" -ne 2 ]; then
                echo -e "${RED}Error: Connection ID not specified.${NC}"
                show_help
                exit 1
            fi
            stop_connection "$2"
            ;;
        stopall)
            stop_all_connections
            ;;
        help)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Invalid command '${1}'${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
