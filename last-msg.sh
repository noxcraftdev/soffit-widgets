#!/bin/bash
# Show the time of the last Claude response in this session
INPUT=$(cat)
COMPACT=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config',{}).get('compact',False))" 2>/dev/null)

TIMESTAMP=$(date +%H:%M:%S)

if [ "$COMPACT" = "True" ]; then
  echo "{\"output\": \"$TIMESTAMP\", \"components\": [\"time\"]}"
else
  echo "{\"output\": \"Last Msg: $TIMESTAMP\", \"components\": [\"time\"]}"
fi
