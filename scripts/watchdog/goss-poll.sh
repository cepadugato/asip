#!/bin/bash
exec > >(logger -t goss-poll) 2>&1
HOSTNAME=$(hostname)
RESULT=$(goss -g /etc/goss/goss.yaml validate --format json 2>/dev/null)
FAILED=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['failed-count'])" 2>/dev/null || echo 0)
if [ "$FAILED" -gt 0 ]; then
    ENRICHED=$(echo "$RESULT" | python3 -c "
import json,sys
d = json.load(sys.stdin)
d['host'] = '$HOSTNAME'
d['ip'] = '127.0.0.1'
d['failed_checks'] = []
for r in d.get('results', []):
    if not r.get('successful', True):
        d['failed_checks'].append({'type': r.get('resource-type','?').lower(), 'resource': r.get('resource-id','?')})
print(json.dumps(d))
")
    curl -sf -X POST http://localhost:8080/webhook/goss -H 'Content-Type: application/json' -d "$ENRICHED"
fi
