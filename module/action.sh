#!/system/bin/sh
# Report state; never clear cached apps or launch app compilation here.
sh "${0%/*}/memory-pressure-policy.sh" status
sh "${0%/*}/guard-policy.sh" status
sh "${0%/*}/oem-diagnostics-policy.sh" status
sh "${0%/*}/radio-scan-policy.sh" status
