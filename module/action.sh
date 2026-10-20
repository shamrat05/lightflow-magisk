#!/system/bin/sh
# Report state; never clear cached apps or launch app compilation here.
sh "${0%/*}/memory-pressure-policy.sh" status
sh "${0%/*}/guard-policy.sh" status
