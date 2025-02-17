#!/bin/bash
set -e

# Function to print error message and exit
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to generate JWT
generate_jwt() {
    local username="$1"
    local password="$2"
    local secret="$3"

    # Validate inputs
    [[ -z "$username" || -z "$password" ]] && error_exit "Username and password are required for JWT generation"

    header='{"alg":"HS256","typ":"JWT"}'
    payload="{\"username\":\"$username\",\"password\":\"$password\"}"

    # Base64url encode header and payload
    header_base64=$(echo -n "$header" | openssl base64 -A | tr -d '=' | tr '/+' '_-')
    payload_base64=$(echo -n "$payload" | openssl base64 -A | tr -d '=' | tr '/+' '_-')

    # Generate signature
    if [[ -z "$secret" ]]; then
        # Handle empty secret case properly
        signature=""
    else
        signature=$(echo -n "${header_base64}.${payload_base64}" |
                  openssl dgst -sha256 -hmac "$secret" -binary |
                  openssl base64 -A | tr -d '=' | tr '/+' '_-')
    fi

    # Concatenate to form the JWT
    jwt_token="${header_base64}.${payload_base64}.${signature}"
    echo "$jwt_token"
}

# Function to get deployment status
get_deployment_status() {
    local base_url="$1"
    local auth_header="$2"
    local cookie_header="$3"
    local task_id="$4"
    local timeout=600  # 10 minutes timeout
    local start_time=$(date +%s)

    echo "Checking deployment status..."

    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        if [[ $elapsed -gt $timeout ]]; then
            error_exit "Deployment timed out after $(($timeout / 60)) minutes"
        fi

        response=$(curl --silent --location "$base_url/getDeploymentStatus/?task_id=$task_id" \
            --header "$auth_header" \
            --header "$cookie_header" || echo '{"response":[{"status":"error","msg":"Connection failed"}]}')

        # Check if jq command succeeded
        status=$(echo "$response" | jq -r '.response[0].status' 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "Failed to parse response: $response"
            sleep 5
            continue
        fi

        message=$(echo "$response" | jq -r '.response[0].msg')

        case "$status" in
            success)
                echo "Deployment completed successfully: $message"
                return 0
                ;;
            failure)
                error_exit "Deployment failed: $message"
                ;;
            error)
                echo "Received error: $message. Retrying..."
                ;;
            *)
                echo "Deployment in progress... (Status: ${status:-unknown})"
                ;;
        esac

        sleep 5
    done
}

# Function to deploy a branch and get deployment status
deploy() {
    local base_url="$1"
    local auth_header="$2"
    local cookie_header="$3"
    local branch="$4"
    local release_notes="$5"

    echo "Starting deployment of branch: $branch"
    echo "Release notes: $release_notes"

    # Validate base URL
    [[ "$base_url" != http* ]] && error_exit "Invalid base URL: $base_url"

    local curl_command="curl --silent --location \"$base_url/deploy/\" \
        --header \"$auth_header\" \
        --header \"$cookie_header\" \
        --header \"Content-Type: application/json\" \
        --data \"{\\\"branch\\\": \\\"$branch\\\", \\\"release_notes\\\": \\\"$release_notes\\\"}\""

    echo "Executing: $curl_command"
    response=$(eval "$curl_command")

    if [[ -z "$response" ]]; then
        error_exit "Empty response received from deployment endpoint"
    fi

    # Check if jq command succeeded
    task_id=$(echo "$response" | jq -r '.response.task_id' 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        error_exit "Failed to parse response: $response"
    fi

    if [[ "$task_id" == "null" || -z "$task_id" ]]; then
        error_exit "Failed to retrieve task ID. Response: $response"
    fi

    echo "Deployment started. Task ID: $task_id"
    get_deployment_status "$base_url" "$auth_header" "$cookie_header" "$task_id"
}

# Main script
main() {
    # Check dependencies
    command -v jq >/dev/null 2>&1 || error_exit "jq is required but not installed. Please install jq"
    command -v curl >/dev/null 2>&1 || error_exit "curl is required but not installed. Please install curl"
    command -v openssl >/dev/null 2>&1 || error_exit "openssl is required but not installed. Please install openssl"

    if [[ $# -ne 8 ]]; then
        echo "Usage: $0 <base_url> <ZELTHY_TOKEN> <GITHUB_USERNAME> <GITHUB_TOKEN> <branch> <release_notes> <GITHUB_OWNER> <GITHUB_REPO>"
        exit 1
    fi

    # Trim trailing slashes from base URL
    local base_url="$1"
    local zelthy_token="$2"
    local github_username="$3"
    local github_token="$4"
    local branch="$5"
    local release_notes="$6"
    local github_owner="$7"
    local github_repo="$8"

    # Validate required parameters
    [[ -z "$base_url" ]] && error_exit "Base URL is required"
    [[ -z "$zelthy_token" ]] && error_exit "ZELTHY_TOKEN is required"
    [[ -z "$github_username" ]] && error_exit "GITHUB_USERNAME is required"
    [[ -z "$github_token" ]] && error_exit "GITHUB_TOKEN is required"
    [[ -z "$branch" ]] && error_exit "Branch name is required"

    # Generate GitHub JWT
    echo "Generating GitHub JWT token..."
    local github_jwt=$(generate_jwt "$github_username" "$github_token" "")
    local auth_header="Authorization: Bearer $zelthy_token"
    local cookie_header="Cookie: github_auth=$github_jwt; owner=$github_owner; repo_name=$github_repo"

    # Start deployment
    deploy "$base_url" "$auth_header" "$cookie_header" "$branch" "$release_notes"

    echo "Deployment process completed"
}

# Run the main function
main "$@"
