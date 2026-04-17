#!/usr/bin/env bash
# poststart.local.sh — project-local post-start setup.
#
# This script is sourced at the end of poststart.sh every time the container
# starts. Use it for project-specific startup steps.
#
# This file is never overwritten by upstream updates.
#
# Examples:
#   export DATABASE_URL=postgres://localhost/myapp
#   ./scripts/start-services.sh
