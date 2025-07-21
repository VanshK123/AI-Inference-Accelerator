#!/bin/sh
# Setup script for TSMC 5nm PDK
PDK_ROOT="$(dirname "$(readlink -f "$0")")"
export PDK_ROOT

PDK_ENV="$PDK_ROOT/tsmc5nm/env.sh"
if [ -f "$PDK_ENV" ]; then
    . "$PDK_ENV"
else
    echo "PDK environment file not found: $PDK_ENV" >&2
    exit 1
fi

# verify required library paths
LIB_DIR="$PDK_ROOT/lib"
TECH_FILE="$PDK_ROOT/tech/tsmc5nm.tf"

if [ ! -d "$LIB_DIR" ] || [ ! -f "$TECH_FILE" ]; then
    echo "Missing PDK libraries or techfile" >&2
    exit 1
fi

echo "PDK configured at $PDK_ROOT"
