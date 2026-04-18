#!/usr/bin/env bash
# poststart.local.sh — project-local post-start setup.
#
# This script is sourced (not subshelled) at the end of poststart.sh every time
# the container starts. Use it for project-specific startup steps.
# Exported variables and functions will be visible to poststart.sh.
#
# This file is never overwritten by upstream updates.
#
# Examples:
#   export DATABASE_URL=postgres://localhost/myapp
#   ./scripts/start-services.sh
