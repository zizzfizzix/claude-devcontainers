#!/usr/bin/env bash
# postcreate.local.sh — project-local post-create setup.
#
# This script is sourced at the end of postcreate.sh after the container is
# first created. Use it for project-specific one-time setup steps.
#
# This file is never overwritten by upstream updates.
#
# Examples:
#   npm install
#   composer install
#   cp .env.example .env
