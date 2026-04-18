#!/usr/bin/env bash
set -euo pipefail

# WP-CLI — fetch latest release tag from GitHub if version not pinned via env
if [ -z "${WP_CLI_VERSION:-}" ]; then
    WP_CLI_VERSION=$(curl -fsSL https://api.github.com/repos/wp-cli/wp-cli/releases/latest \
        | jq -r '.tag_name | ltrimstr("v")')
fi
if [ -z "$WP_CLI_VERSION" ]; then
    echo "ERROR: Failed to determine WP-CLI version; set WP_CLI_VERSION to override" >&2
    exit 1
fi
sudo curl -sL "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
  -o /usr/local/bin/wp
sudo chmod +x /usr/local/bin/wp
