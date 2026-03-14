#!/usr/bin/env bash
set -euo pipefail

# WP-CLI
WP_CLI_VERSION="${WP_CLI_VERSION:-2.10.0}"
sudo curl -sL "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
  -o /usr/local/bin/wp
sudo chmod +x /usr/local/bin/wp
