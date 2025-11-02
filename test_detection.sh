#!/bin/bash

echo "=== Distro Detection Diagnostics ==="
echo ""
echo "Distro Files:"
[[ -f /etc/arch-release ]] && echo "  ✓ /etc/arch-release EXISTS" || echo "  ✗ /etc/arch-release MISSING"
[[ -f /etc/asahi-release ]] && echo "  ✓ /etc/asahi-release EXISTS" || echo "  ✗ /etc/asahi-release MISSING"
[[ -f /etc/debian_version ]] && echo "  ✓ /etc/debian_version EXISTS" || echo "  ✗ /etc/debian_version MISSING"
[[ -f /etc/fedora-release ]] && echo "  ✓ /etc/fedora-release EXISTS" || echo "  ✗ /etc/fedora-release MISSING"
[[ -f /etc/redhat-release ]] && echo "  ✓ /etc/redhat-release EXISTS" || echo "  ✗ /etc/redhat-release MISSING"

echo ""
echo "Available Package Managers:"
command -v apt-get &> /dev/null && echo "  ✓ apt-get" || echo "  ✗ apt-get"
command -v pacman &> /dev/null && echo "  ✓ pacman" || echo "  ✗ pacman"
command -v dnf &> /dev/null && echo "  ✓ dnf" || echo "  ✗ dnf"
command -v yum &> /dev/null && echo "  ✓ yum" || echo "  ✗ yum"

echo ""
echo "System Info:"
echo "  OS: $(uname -s)"
echo "  Arch: $(uname -m)"
[[ -f /etc/os-release ]] && echo "  ID: $(grep ^ID= /etc/os-release | cut -d= -f2)"

echo ""
echo "What detection would pick:"
# Inline the detection logic
if [[ -f /etc/arch-release ]] || [[ -f /etc/asahi-release ]]; then
    echo "  → pacman (via distro files)"
elif [[ -f /etc/debian_version ]]; then
    echo "  → apt (via distro files)"
elif [[ -f /etc/fedora-release ]]; then
    echo "  → dnf (via distro files)"
elif [[ -f /etc/redhat-release ]] && command -v dnf &> /dev/null; then
    echo "  → dnf (via redhat + dnf command)"
elif [[ -f /etc/redhat-release ]] && command -v yum &> /dev/null; then
    echo "  → yum (via redhat + yum command)"
elif command -v apt-get &> /dev/null; then
    echo "  → apt (via command fallback)"
elif command -v pacman &> /dev/null; then
    echo "  → pacman (via command fallback)"
elif command -v dnf &> /dev/null; then
    echo "  → dnf (via command fallback)"
elif command -v yum &> /dev/null; then
    echo "  → yum (via command fallback)"
else
    echo "  → unknown"
fi
