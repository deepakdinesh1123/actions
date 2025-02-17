#!/bin/bash

# Function to deploy a branch and get deployment status
deploy() {
    local base_url="$1"
    local auth_header="$2"
    local cookie_header="$3"
    local branch="$4"
    local release_notes="$5"

    response=$(curl --silent --location "$base_url/deploy/" \
        --header "$auth_header" \
        --header "$cookie_header" \
        --header "Content-Type: application/json" \
        --data "{\"branch\": \"$branch\", \"release_notes\": \"$release_notes\"}")

    task_id=$(echo "$response" | jq -r '.response.task_id')
    echo "Deployment started. Task ID: $task_id"

    if [[ "$task_id" != "null" ]]; then
        get_deployment_status "$base_url" "$auth_header" "$cookie_header" "$task_id"
    else
        echo "Failed to retrieve task ID. Response: $response"
    fi
}

# Function to get deployment status
get_deployment_status() {
    local base_url="$1"
    local auth_header="$2"
    local cookie_header="$3"
    local task_id="$4"

    while true; do
        response=$(curl --silent --location "$base_url/getDeploymentStatus/?task_id=$task_id" \
            --header "$auth_header" \
            --header "$cookie_header")

        status=$(echo "$response" | jq -r '.response[0].status')
        message=$(echo "$response" | jq -r '.response[0].msg')

        if [[ "$status" == "success" || "$status" == "failure" ]]; then
            echo "Deployment status: $status - $message"
            break
        else
            echo "Deployment in progress..."
            sleep 5
        fi
    done
}


if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <base_url> <auth_token> <cookie> <branch> <release_notes>"
    exit 1
fi

BASE_URL="$1"
AUTH_TOKEN="$2"
COOKIE="$3"
BRANCH="$4"
RELEASE_NOTES="$5"

AUTH_HEADER="Authorization: Bearer $AUTH_TOKEN"
COOKIE_HEADER="Cookie: $COOKIE"

deploy "$BASE_URL" "$AUTH_HEADER" "$COOKIE_HEADER" "$BRANCH" "$RELEASE_NOTES"
