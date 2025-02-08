#!/bin/bash

VERSION="2.1"
DEFAULT_INTERVAL=60
DEFAULT_PING_HOST="google.com"
DEFAULT_PING_PORT=443
DEFAULT_PING_TIMEOUT=2
DEFAULT_CURL_TIMEOUT=10
LOGGING_ENABLED=false

# Telegram settings
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
TELEGRAM_API_URL="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            URL=$2
            shift 2
            ;;
        -i|--interval)
            INTERVAL=$2
            shift 2
            ;;
        -p|--ping-host)
            PING_HOST=$2
            shift 2
            ;;
        -t|--ping-timeout)
            PING_TIMEOUT=$2
            shift 2
            ;;
        -c|--curl-timeout)
            CURL_TIMEOUT=$2
            shift 2
            ;;
        -P|--ping-port)
            PING_PORT=$2
            shift 2
            ;;
        -l|--log)
            if [[ $2 == "on" ]]; then
                LOGGING_ENABLED=true
            else
                LOGGING_ENABLED=false
            fi
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validation
if [[ -z "$URL" ]]; then
    echo "Error: URL is required (use --url)" >&2
    exit 1
fi

# Set defaults
INTERVAL=${INTERVAL:-$DEFAULT_INTERVAL}
PING_HOST=${PING_HOST:-$DEFAULT_PING_HOST}
PING_PORT=${PING_PORT:-$DEFAULT_PING_PORT}
PING_TIMEOUT=${PING_TIMEOUT:-$DEFAULT_PING_TIMEOUT}
CURL_TIMEOUT=${CURL_TIMEOUT:-$DEFAULT_CURL_TIMEOUT}

# Function to send Telegram notification
send_telegram_notification() {
    local message=$1
    ip=$(hostname -I | awk '{ print $1 }')
    server_info=$(curl -s http://ip-api.com/json | jq -r '.isp + ", " + .city')
    local full_message="$message\nIP: $ip. Server: $server_info."
    curl -s -X POST "$TELEGRAM_API_URL" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$full_message" > /dev/null
}

# TCP ping measurement using netcat (nc)
measure_tcp_ping() {
    local host=$1
    local port=$2
    local timeout=$3

    if $LOGGING_ENABLED; then
        echo "Measuring TCP ping to $host:$port with timeout $timeout sec..." >&2
    fi
    local start_time=$(date +%s%N) # Get nanosecond time

    if nc -z -w "$timeout" "$host" "$port" 2>/dev/null; then
        local end_time=$(date +%s%N)
        local time_ms=$(( (end_time - start_time) / 1000000 )) # Convert ns to ms
        echo "$time_ms"
        return 0
    else
        if $LOGGING_ENABLED; then
            echo "TCP ping failed to $host:$port (timeout: ${timeout}s)" >&2
        fi
        send_telegram_notification "Host $host:$port is unreachable or timed out (timeout: ${timeout}s)."
        return 1
    fi
}

# Main loop
if $LOGGING_ENABLED; then
    echo "kuma-push v$VERSION started | URL: $URL | TCP ping: ${PING_HOST}:${PING_PORT} | Ping timeout: ${PING_TIMEOUT}s | Curl timeout: ${CURL_TIMEOUT}s" >&2
fi

while true; do
    loop_start_time=$(date +%s)

    if tcp_ping_result=$(measure_tcp_ping "$PING_HOST" "$PING_PORT" "$PING_TIMEOUT"); then
        req_url="${URL}${tcp_ping_result}"
        ping_status="[TCP PING: SUCCESS ${tcp_ping_result}ms]"
    else
        req_url="${URL}"
        ping_status="[TCP PING: FAILED]"
    fi

    if $LOGGING_ENABLED; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $ping_status | URL: $req_url" >&2
        echo "Sending request to: $req_url" >&2
    fi
    
    curl_output=$(curl -X GET -s -o /dev/null --max-time "$CURL_TIMEOUT" -w "%{http_code}" "$req_url")
    curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        case $curl_exit_code in
            6)  error_message="DNS resolution failed for host: $(echo "$req_url" | awk -F[/:] '{print $4}')." ;;
            7)  error_message="Connection to $(echo "$req_url" | awk -F[/:] '{print $4}') refused." ;;
            28) error_message="Connection to $(echo "$req_url" | awk -F[/:] '{print $4}') timed out after ${CURL_TIMEOUT}s." ;;
            35) error_message="SSL/TLS handshake failed for $(echo "$req_url" | awk -F[/:] '{print $4}')." ;;
            22) error_message="HTTP error: $curl_output for $(echo "$req_url" | awk -F[/:] '{print $4}')." ;;
            *)  error_message="Unknown error occurred while connecting to $(echo "$req_url" | awk -F[/:] '{print $4}'). Curl exit code: $curl_exit_code." ;;
        esac
        if $LOGGING_ENABLED; then
            echo "$error_message" >&2
        fi
        send_telegram_notification "$error_message"
    fi

    # Adjust sleep time to maintain consistent interval execution
    current_time=$(date +%s)
    elapsed_time=$((current_time - loop_start_time))
    sleep_time=$((INTERVAL - elapsed_time))

    if (( sleep_time > 0 )); then
        if $LOGGING_ENABLED; then
            echo "Sleeping for $sleep_time sec..." >&2
        fi
        sleep "$sleep_time"
    else
        if $LOGGING_ENABLED; then
            echo "Warning: Loop execution took ${elapsed_time} sec (interval: ${INTERVAL} sec)" >&2
        fi
    fi
done
