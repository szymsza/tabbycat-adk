#!/bin/bash

# Build and restart Docker containers in the background
# Output is logged to /tmp/deploy-{timestamp}.log

# Generate timestamp for log file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="/tmp/deploy-${TIMESTAMP}.log"

nohup bash -c 'docker compose -f docker-compose.yml -f docker-compose.prod.yml build && docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d' > "$LOGFILE" 2>&1 &

disown

echo "Docker rebuild started in background."
echo "Log file: $LOGFILE"
echo "To monitor: tail -f $LOGFILE"
