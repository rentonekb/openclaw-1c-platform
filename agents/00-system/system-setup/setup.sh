#!/bin/bash
set -euo pipefail
sysctl -w vm.max_map_count=262144
sysctl -w fs.file-max=65536
echo "vm.max_map_count=262144" >> /etc/sysctl.d/99-openclaw.conf
echo "fs.file-max=65536" >> /etc/sysctl.d/99-openclaw.conf
sysctl -p /etc/sysctl.d/99-openclaw.conf
