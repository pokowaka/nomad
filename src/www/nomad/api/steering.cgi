#!/bin/sh
#
# Project Nomad: The API Gateway
# /www/nomad/api/steering.cgi
#
# Runs as root via uhttpd. Receives JSON POST to update steering rules.

. /usr/share/libubox/jshn.sh

# --- Functions ---
json_error_and_exit() {
    echo "Content-type: application/json"
    echo ""
    echo "{ \"status\": \"error\", \"message\": \"$1\" }"
    exit 1
}

json_ok_and_exit() {
    echo "Content-type: application/json"
    echo ""
    echo "{ \"status\": \"ok\", \"message\": \"$1\" }"
    exit 0
}


# --- Main Execution ---

# 1. Read POST data from stdin
[ -z "$CONTENT_LENGTH" ] && json_error_and_exit "No POST data received."
read -n "$CONTENT_LENGTH" post_data

# 2. Parse JSON and validate
json_load "$post_data"
json_get_var ip ip
json_get_var table table

[ -z "$ip" ] || [ -z "$table" ] && json_error_and_exit "Missing 'ip' or 'table' in JSON payload."

# 3. Call backend script to apply the change.
# The 'nomad-steer' script contains the necessary logic for validation,
# atomic updates, and route application. We capture its output.
output=$(/usr/bin/nomad-steer set "$ip" "$table" 2>&1)
result=$?

# 4. Return status to client
if [ $result -eq 0 ]; then
    json_ok_and_exit "Rule for $ip updated successfully."
else
    # Sanitize output before returning to client for security.
    sanitized_output=$(echo "$output" | sed 's/[^a-zA-Z0-9 _.-]//g')
    json_error_and_exit "Failed to apply rule: $sanitized_output"
fi
