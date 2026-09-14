#!/bin/bash

# Git pull/fetch script with flexible branch management
# Usage:
#   ./pull.sh                    - Fetch all branches, pull current branch
#   ./pull.sh <branch>           - Fetch all, checkout and pull local branch
#   ./pull.sh <branch> <remote>  - Fetch all, checkout remote branch

# Fetch all branches from all remotes
echo "Fetching all branches..."
git fetch --all

# If no arguments, just pull current branch
if [ $# -eq 0 ]; then
    echo "Pulling current branch..."
    git pull
    echo "Done!"
    exit 0
fi

BRANCH=$1
REMOTE=${2:-}

# If remote is specified, checkout the remote branch
if [ -n "$REMOTE" ]; then
    echo "Checking out remote branch: ${REMOTE}/${BRANCH}"
    git checkout -B "$BRANCH" "${REMOTE}/${BRANCH}"
    echo "Done!"
else
    # Just checkout and pull local branch
    echo "Checking out local branch: ${BRANCH}"
    git checkout "$BRANCH"
    echo "Pulling ${BRANCH}..."
    git pull
    echo "Done!"
fi
