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
        "tcp"|"http")
            local ports="80 443 3000 3306 5432 8000 8080 8443 9000"
            COMPREPLY=( $(compgen -W "$ports" -- "$cur") )
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
            echo "" >> "$HOME/.bashrc"
            echo "# NetCtl completion" >> "$HOME/.bashrc"
            echo "if [ -f \"$completion_file\" ]; then" >> "$HOME/.bashrc"
            echo "    source \"$completion_file\"" >> "$HOME/.bashrc"
            echo "fi" >> "$HOME/.bashrc"
            source ~/.bashrc
        fi
    fi
}

# Function to detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
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
                sshpass)
                    to_install+=("sshpass")
                    ;;
                jq)
                    to_install+=("jq")
                    ;;
                curl)
                    to_install+=("curl")
                    ;;
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
            # Direct root execution
            $INSTALL_CMD "${to_install[@]}"
        else
            # Use sudo
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

# Function to check dependencies
check_dependencies() {
    local required_deps=("jq" "sshpass" "curl" "ssh")
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
   echo -e "  $(basename "$0") ${GREEN}tcp${NC} <port>                            - Run TCP tunneling"
   echo -e "  $(basename "$0") ${GREEN}http${NC} <port> [-c <domain>]             - Run HTTP tunneling"
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

# Function to handle browser login flow
browser_login() {
    local hub_base="https://hub.netctl.net"
    local uuid_str
    uuid_str=$(cat /proc/sys/kernel/random/uuid)
    local login_url="${hub_base}/login?uuid=${uuid_str}"
    local poll_interval=2
    local timeout_minutes=5
    local start_time=$(date +%s)
    local timeout_seconds=$((timeout_minutes * 60))

    echo -e "${CYAN}Initiating browser login...${NC}"
    echo -e ""
    echo -e "${PURPLE}UUID: ${GOLD}${uuid_str}${NC}"
    echo -e ""
    echo -e "${YELLOW}Please open this URL in your browser and complete the CAPTCHA + TOTP:${NC}"
    echo -e "${CYAN}${login_url}${NC}"
    echo -e ""
    echo -e "${PURPLE}Waiting for login to complete (up to ${timeout_minutes} minutes)...${NC}"

    # Start polling for token
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout_seconds ]; then
            echo -e ""
            echo -e "${RED}Login timed out after ${timeout_minutes} minutes. Please try again.${NC}"
            return 1
        fi

        # Poll the API
        local response
        response=$(curl -s --connect-timeout 10 "${hub_base}/api/check-login/${uuid_str}")

        if [ $? -eq 0 ]; then
            local login_status
            login_status=$(echo "$response" | jq -r '.login // false')

            if [ "$login_status" = "true" ]; then
                local token
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
        local error_code
        local error_message

        error_code=$(echo "$response" | jq -r '.error.code' 2>/dev/null)
        error_message=$(echo "$response" | jq -r '.error.message' 2>/dev/null)

        case $error_code in
            401)
                echo -e "${RED}Error: Invalid token. Please get a new token from the dashboard.${NC}" >&2
                ;;
            403)
                echo -e "${RED}Error: $error_message${NC}" >&2
                ;;
            404)
                echo -e "${RED}Error: Domain not found or inactive.${NC}" >&2
                ;;
            503)
                echo -e "${RED}Error: Service temporarily unavailable. Please try again later.${NC}" >&2
                ;;
            *)
                echo -e "${RED}Error: Unknown error occurred - $error_message${NC}" >&2
                ;;
        esac
        return 1
    fi

    return 0
}

# Function to make API request
get_connection_details() {
    local connection_type=$1
    local custom_domain=$2
    local token
    token=$(cat "$TOKEN_FILE")

    local request_data
    if [ -n "$custom_domain" ]; then
        request_data="{\"Token\":\"$token\", \"Connection-Type\":\"$connection_type\", \"domain\":\"$custom_domain\"}"
    else
        request_data="{\"Token\":\"$token\", \"Connection-Type\":\"$connection_type\"}"
    fi

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        "https://api.netctl.net/connect-user")

    [ -z "$response" ] && echo -e "${RED}Error: Empty API response${NC}" >&2 && return 1 || echo "$response" | jq . >/dev/null 2>&1 || { echo -e "${RED}Error: Invalid JSON response: '$response'${NC}" >&2; return 1; }

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to connect to the API.${NC}" >&2
        return 1
    fi

    # Check for error codes in the response
    local error_code
    error_code=$(echo "$response" | jq -r '.error.code // empty')

    if [ -n "$error_code" ]; then
        handle_api_response "$response"
        return 1
    fi

    # Process successful response
    if handle_api_response "$response"; then
        local remote_port
        remote_port=$(echo "$response" | jq -r '.data.port')
        local in_use=false

        for conn_file in "$CONNECTIONS_DIR"/*.json; do
            if [ -f "$conn_file" ]; then
                local existing_remote_port
                existing_remote_port=$(jq -r '.remote_port' "$conn_file")
                local existing_pid
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

# Function to save connection details
save_connection_details() {
    local conn_id=$1
    local conn_type=$2
    local local_port=$3
    local remote_port=$4
    local hostname=$5
    local pid=$6
    local custom_domain=$7
    local endpoint=$8

    mkdir -p "$CONNECTIONS_DIR"
    if [ -n "$custom_domain" ]; then
        cat > "$CONNECTIONS_DIR/$conn_id.json" << EOF
{
    "id": "$conn_id",
    "type": "$conn_type",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "hostname": "$hostname",
    "CNAME": "$endpoint",
    "custom_domain": "$custom_domain",
    "pid": $pid,
    "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    else
        cat > "$CONNECTIONS_DIR/$conn_id.json" << EOF
{
    "id": "$conn_id",
    "type": "$conn_type",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "hostname": "$hostname",
    "pid": $pid,
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
        if ss -Htln | grep -q ":$port\b"; then
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

# Modified SSH background function
run_ssh_background() {
    local conn_id=$1
    local user_pass=$2
    local local_port=$3
    local endpoint=$4
    local hostname=$5
    local remote_port=$6
    local connection_type=$7
    local custom_domain=$8
    local max_retries=3
    local retry_delay=3
    local check_delay=2

    local username
    username=$(echo "$user_pass" | base64 --decode | cut -d: -f1)
    local password
    password=$(echo "$user_pass" | base64 --decode | cut -d: -f2)

    # Export password for sshpass
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
            -N -R "$([[ $connection_type == tcp ]] && echo "0.0.0.0:" || echo "")$remote_port:127.0.0.1:$local_port" \
            >/dev/null 2>&1 &

        local pid=$!
        unset SSHPASS

        sleep $check_delay

        if is_process_running "$pid"; then
            sleep $check_delay
            if is_process_running "$pid"; then
                save_connection_details "$conn_id" "$connection_type" "$local_port" "$remote_port" "$hostname" "$pid" "$custom_domain" "$endpoint"

                echo -e "${GREEN}Connection started successfully!${NC}"
                echo -e "${PURPLE}Connection ID: ${GOLD}$conn_id${NC}"
                echo -e "${PURPLE}Type: ${GOLD}${connection_type}${NC}"
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

# Function to list active connections
list_connections() {
   if [ ! -d "$CONNECTIONS_DIR" ] || [ -z "$(ls -A "$CONNECTIONS_DIR")" ]; then
       echo -e "${GOLD}No active connections.${NC}"
       return
   fi

   echo -e "${CYAN}Active Connections:${NC}"
   echo -e "${PURPLE}----------------------------------------${NC}"

   for conn_file in "$CONNECTIONS_DIR"/*.json; do
       [ -f "$conn_file" ] || continue

       local conn_data
       conn_data=$(cat "$conn_file")
       local conn_id
       conn_id=$(echo "$conn_data" | jq -r '.id')
       local conn_type
       conn_type=$(echo "$conn_data" | jq -r '.type')
       local local_port
       local_port=$(echo "$conn_data" | jq -r '.local_port')
       local remote_port
       remote_port=$(echo "$conn_data" | jq -r '.remote_port')
       local hostname
       hostname=$(echo "$conn_data" | jq -r '.hostname')
       local hostname
       CNAME=$(echo "$conn_data" | jq -r '.CNAME')
       local custom_domain
       custom_domain=$(echo "$conn_data" | jq -r '.custom_domain // empty')
       local pid
       pid=$(echo "$conn_data" | jq -r '.pid')
       local started_at
       started_at=$(echo "$conn_data" | jq -r '.started_at')

       if is_process_running "$pid"; then
           local status="${GREEN}ACTIVE${NC}"
       else
           local status="${RED}DEAD${NC}"
           # Clean up dead connection
           rm "$conn_file"
           continue
       fi

       echo -e "${PURPLE}ID: ${GOLD}$conn_id${NC}"
       echo -e "${PURPLE}Type: ${GOLD}$conn_type${NC}"
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

    local pid
    pid=$(cat "$conn_file" | jq -r '.pid')

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

    rm "$conn_file"
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
            local port=""
            local custom_domain=""

            while [ $# -gt 0 ]; do
                case "$1" in
                    -c|--custom_domain)
                        if [ "$command" != "http" ]; then
                            echo -e "${RED}Error: Custom domain can only be used with HTTP connections${NC}"
                            exit 1
                        fi
                        custom_domain="$2"
                        shift 2
                        ;;
                    *)
                        if [ -z "$port" ]; then
                            port="$1"
                            shift
                        else
                            echo -e "${RED}Error: Unexpected argument '$1'${NC}"
                            show_help
                            exit 1
                        fi
                        ;;
                esac
            done

            if ! [[ "$port" =~ ^[1-9][0-9]*$ ]] || [ "$port" -gt 65535 ]; then
                echo -e "${RED}Error: Invalid port number. Port must be a number between 1 and 65535.${NC}"
                show_help
                exit 1
            fi

            check_token_exists
            check_internet || exit 1

            local response
            response=$(get_connection_details "$command" "$custom_domain") || exit 1

            local endpoint
            endpoint=$(echo "$response" | jq -r '.data.endpoint')
            local hostname
            hostname=$(echo "$response" | jq -r '.data.hostname')
            local remote_port
            remote_port=$(echo "$response" | jq -r '.data.port')

            local conn_id
            conn_id=$(generate_connection_id)
            local token
            token=$(cat "$TOKEN_FILE")

            run_ssh_background "$conn_id" "$token" "$port" "$endpoint" "$hostname" "$remote_port" "$command" "$custom_domain"
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
