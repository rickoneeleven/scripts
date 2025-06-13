#!/bin/bash

# DNS Monitoring Script
# Accepts comma-separated DNS servers and tests them against external domains
# Records response times in JSON format and displays averages

# Check if DNS servers parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <dns_servers>"
    echo "Example: $0 172.24.0.10,8.8.4.4"
    exit 1
fi

# Configuration
DNS_SERVERS_INPUT="$1"
IFS=',' read -ra DNS_SERVERS <<< "$DNS_SERVERS_INPUT"
DOMAINS=(
    "bbc.co.uk"
    "wrc.com"
    "google.co.uk"
    "channel4.com"
    "amazon.co.uk"
    "microsoft.com"
    "cloudflare.com"
    "github.com"
    "stackoverflow.com"
    "wikipedia.org"
)
OUTPUT_FILE="dns_performance.json"
TEMP_FILE="/tmp/dns_test_current.tmp"
LAST_RESULTS_FILE="/tmp/dns_last_results.tmp"

# Initialize JSON file if it doesn't exist
if [ ! -f "$OUTPUT_FILE" ]; then
    echo '{"tests": []}' > "$OUTPUT_FILE"
fi

# Function to generate random subdomain for cache busting
generate_random_subdomain() {
    echo "test-$(date +%s)-$(shuf -i 1000-9999 -n 1)"
}

# Function to measure DNS lookup time
measure_dns_lookup() {
    local server=$1
    local domain=$2
    local cache_bust=$3
    
    if [ "$cache_bust" = "true" ]; then
        # Add random subdomain to force fresh lookup
        local random_sub=$(generate_random_subdomain)
        domain="${random_sub}.${domain}"
    fi
    
    # Use dig with +tries=1 +time=5 for reliable timing
    local start=$(date +%s.%N)
    dig @"$server" "$domain" +tries=1 +time=5 +noall +answer > /dev/null 2>&1
    local exit_code=$?
    local end=$(date +%s.%N)
    
    if [ $exit_code -eq 0 ]; then
        # Calculate duration in milliseconds
        echo "scale=3; ($end - $start) * 1000" | bc
    else
        echo "-1"  # Error indicator
    fi
}

# Function to calculate average from all historical data
calculate_average() {
    local server=$1
    local count=0
    local sum=0
    
    # Use jq if available for better performance
    if command -v jq &> /dev/null && [ -f "$OUTPUT_FILE" ]; then
        local result=$(jq -r ".tests[] | select(.server==\"$server\" and .response_time != -1) | .response_time" "$OUTPUT_FILE" 2>/dev/null | awk '{sum+=$1; count++} END {if (count>0) printf "%.2f", sum/count; else print "N/A"}')
        echo "$result"
    else
        # Fallback: parse JSON manually
        if [ -f "$OUTPUT_FILE" ]; then
            while IFS= read -r line; do
                if [[ $line == *"\"server\": \"$server\""* ]]; then
                    # Look for the response_time in the next few lines
                    local found_time=false
                    for i in {1..5}; do
                        IFS= read -r next_line
                        if [[ $next_line == *"\"response_time\":"* ]]; then
                            local time=$(echo "$next_line" | grep -oP '"response_time": \K-?[0-9.]+')
                            if [ -n "$time" ] && [ "$time" != "-1" ]; then
                                sum=$(echo "$sum + $time" | bc)
                                count=$((count + 1))
                            fi
                            found_time=true
                            break
                        fi
                    done
                fi
            done < "$OUTPUT_FILE"
        fi
        
        if [ $count -eq 0 ]; then
            echo "N/A"
        else
            echo "scale=2; $sum / $count" | bc
        fi
    fi
}

# Function to get last result for a server
get_last_result() {
    local server=$1
    local total=0
    local count=0
    
    if [ -f "$LAST_RESULTS_FILE" ]; then
        while IFS= read -r line; do
            if [[ $line == *"\"server\":\"$server\""* ]]; then
                local time=$(echo "$line" | grep -oP '"response_time":\K-?[0-9.]+')
                if [ -n "$time" ] && [ "$time" != "-1" ]; then
                    total=$(echo "$total + $time" | bc)
                    count=$((count + 1))
                fi
            fi
        done < "$LAST_RESULTS_FILE"
    fi
    
    if [ $count -eq 0 ]; then
        echo "N/A"
    else
        echo "scale=2; $total / $count" | bc
    fi
}

# Function to display status
display_status() {
    clear
    echo "=== DNS Monitoring Status ==="
    echo "Last update: $(date)"
    echo ""
    echo "Response Times (ms):"
    echo "Server               | Last Run     | Average      | Diff"
    echo "---------------------------------------------------------"
    
    for server in "${DNS_SERVERS[@]}"; do
        local last=$(get_last_result "$server")
        local avg=$(calculate_average "$server")
        
        # Calculate difference if both values exist
        local diff="N/A"
        if [ "$last" != "N/A" ] && [ "$avg" != "N/A" ]; then
            diff=$(echo "scale=2; $last - $avg" | bc)
            # Add + sign for positive differences
            if (( $(echo "$diff > 0" | bc -l) )); then
                diff="+$diff"
            fi
        fi
        
        printf "%-20s | %-9s ms | %-9s ms | %s ms\n" "$server" "$last" "$avg" "$diff"
    done
    
    echo ""
    echo "Next test in: $1 seconds (Press ENTER to test now, 'r' to reset data)"
}

# Main monitoring loop
echo "Starting DNS monitoring..."
echo "Testing DNS servers: ${DNS_SERVERS[*]}"
echo "Against domains: ${DOMAINS[*]}"
echo ""

while true; do
    # Clear temp file for new test run
    > "$TEMP_FILE"
    
    # Timestamp for this test run
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Test each server against each domain
    for server in "${DNS_SERVERS[@]}"; do
        for domain in "${DOMAINS[@]}"; do
            echo -n "Testing $server -> $domain... "
            
            # Perform lookup with cache busting
            response_time=$(measure_dns_lookup "$server" "$domain" "true")
            
            if [ "$response_time" != "-1" ]; then
                echo "${response_time}ms"
            else
                echo "FAILED"
            fi
            
            # Store result in temp file for average calculation
            echo "{\"server\":\"$server\",\"domain\":\"$domain\",\"response_time\":$response_time}" >> "$TEMP_FILE"
            
            # Prepare JSON entry
            json_entry=$(cat <<EOF
{
    "timestamp": "$TIMESTAMP",
    "server": "$server",
    "domain": "$domain",
    "response_time": $response_time,
    "status": $([ "$response_time" != "-1" ] && echo '"success"' || echo '"failed"')
}
EOF
)
            
            # Append to JSON file using jq if available, otherwise use sed
            if command -v jq &> /dev/null; then
                jq ".tests += [$json_entry]" "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
            else
                # Fallback: append manually (less robust but works)
                sed -i '$ s/]$/,/' "$OUTPUT_FILE" 2>/dev/null || sed -i '' '$ s/]$/,/' "$OUTPUT_FILE"
                echo "$json_entry]}" >> "$OUTPUT_FILE"
                sed -i 's/,\]/]/' "$OUTPUT_FILE" 2>/dev/null || sed -i '' 's/,\]/]/' "$OUTPUT_FILE"
            fi
        done
    done
    
    # Copy the just-completed test results to last results file
    cp "$TEMP_FILE" "$LAST_RESULTS_FILE"
    
    # Display countdown with status
    remaining=60
    while [ $remaining -gt 0 ]; do
        display_status "$remaining"
        
        # Check for user input with 10 second timeout
        for j in {1..10}; do
            if [ $remaining -le 0 ]; then
                break
            fi
            
            if read -t 1 -n 1 input; then
                if [ -z "$input" ]; then
                    # ENTER key pressed
                    echo -e "\nForcing immediate test...\n"
                    remaining=0
                    break
                elif [ "$input" = "r" ] || [ "$input" = "R" ]; then
                    # Reset data
                    echo -e "\n\nResetting all DNS monitoring data...\n"
                    echo '{"tests": []}' > "$OUTPUT_FILE"
                    rm -f "$TEMP_FILE" "$LAST_RESULTS_FILE"
                    echo "Data reset complete. Starting fresh...\n"
                    sleep 2
                    remaining=0
                    break
                fi
            fi
            remaining=$((remaining - 1))
        done
    done
done