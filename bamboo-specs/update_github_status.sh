#!/bin/bash

# Check if all required arguments are provided
if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <GITHUB_PAT_TOKEN> <USERNAME> <REPO_NAME> <COMMIT_SHA> <STATE> <TARGET_URL> <DESCRIPTION> <CONTEXT>"
    exit 1
fi

# Assigning command line arguments to variables
GITHUB_PAT_TOKEN=$1
USERNAME=$2
REPO_NAME=$3
COMMIT_SHA=$4
STATE=$5
TARGET_URL=$6
DESCRIPTION=$7
CONTEXT=$8


# Construct the curl command
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Authorization: Bearer $GITHUB_PAT_TOKEN" \
  -d "{\"state\": \"$STATE\", \"target_url\": \"$TARGET_URL\", \"description\": \"$DESCRIPTION\", \"context\": \"$CONTEXT\" }" \
  "https://api.github.com/repos/$USERNAME/$REPO_NAME/statuses/$COMMIT_SHA"
