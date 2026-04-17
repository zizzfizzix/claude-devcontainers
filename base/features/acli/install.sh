#!/bin/bash
set -e

apt-get install -y --no-install-recommends wget gnupg2
install -m 0755 -d /etc/apt/keyrings
wget -qO- https://acli.atlassian.com/gpg/public-key.asc | gpg --dearmor -o /etc/apt/keyrings/acli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/acli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/acli-archive-keyring.gpg] https://acli.atlassian.com/linux/deb stable main" \
  | tee /etc/apt/sources.list.d/acli.list
apt-get update
apt-get install -y acli
