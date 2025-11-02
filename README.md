# Frequency Harvester

> Automated KiwiSDR radio recorder with parallel scanning, visual signal analysis, and podcast feed generation

[![Python 3.9+](https://img.shields.io/badge/python-3.9+-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

Frequency Harvester automates the process of finding, recording, and archiving radio broadcasts from the global [KiwiSDR network](http://kiwisdr.com/). Originally designed for capturing the BBC Shipping Forecast at 198 kHz, it's built to expand to any frequency and broadcast type.

### Key Features

- **⚡ 10x Faster Scanning** - Parallel processing finds best receivers in 1-2 minutes (vs 13+ minutes sequential)
- **📊 Visual Signal Analysis** - Professional output with signal strength bars and quality indicators
- **🎙️ Automated Recording** - Hands-free recording with RSS/podcast feed generation
- **📡 Smart Receiver Selection** - Automatically picks the best receiver based on signal strength
- **🔄 Complete Automation** - One-command setup for cron scheduling

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/lazerdave/frequencyharvester.git
cd frequencyharvester

# Run the automated installer (sudo optional - see below)
bash install_kiwi_recorder.sh
```

**Two Installation Modes:**

1. **With sudo** (recommended for first-time setup):
   ```bash
   sudo bash install_kiwi_recorder.sh
   ```
   - Installs system packages (sox, numpy, scipy, etc.)
   - Auto-detects package manager (apt, dnf, yum, pacman, zypper)
   - Sets up everything automatically

2. **Without sudo** (if system packages already installed):
   ```bash
   bash install_kiwi_recorder.sh
   ```
   - Checks for required dependencies
   - Installs Python packages via pip --user
   - Sets up user directories and scripts
   - **No root access needed**

The installer handles:
- System dependencies (sox, numpy, scipy, requests)
- KiwiSDR client software
- Directory structure
- Python dependencies
- Verification tests

### Basic Usage

```bash
# Find the best receivers (1-2 minutes)
python3 kiwi_recorder.py scan

# Record a broadcast (auto-selects best receiver)
python3 kiwi_recorder.py record

# Generate/update RSS podcast feed
python3 kiwi_recorder.py feed

# Set up automated cron jobs
python3 kiwi_recorder.py setup
```

## Visual Output

The scanner provides professional, at-a-glance signal analysis:

```
════════════════════════════════════════════════════════════════════════════════
  KiwiSDR Network Scanner - Finding Best 198 kHz Receivers
════════════════════════════════════════════════════════════════════════════════
[  1/100] receiver.name:8073        ✓ ████████░░░░  -45.2dB (GOOD) (n=5)
[  2/100] another.host:8073         ✗ TOO WEAK - ██░░░░░░░░░░  -72.1dB (WEAK)
...

┌─ TOP 5 RECEIVERS ─────────────────────────────────────────────────────────────
│ 1. best.receiver:8073              █████████░░░  -42.3dB (VERY GOOD)
│ 2. second.best:8073                ████████░░░░  -45.1dB (GOOD)
└───────────────────────────────────────────────────────────────────────────────
```

## Architecture

**Single-file design** - All functionality consolidated into one 1,022-line Python script with four subcommands:

- `scan` - Parallel network scanning with signal strength measurement
- `record` - Recording with automatic feed updates
- `feed` - RSS/podcast feed generation
- `setup` - Cron automation configuration

**From 4 scripts to 1** - Replaced fragmented codebase with unified, maintainable solution.

## Performance

| Operation | Time | Notes |
|-----------|------|-------|
| Scan (parallel) | 1-2 min | 100 receivers, 15 workers |
| Scan (old sequential) | 13+ min | Previous implementation |
| Recording | 13 min | Configurable duration |
| Feed rebuild | <1 sec | Up to 50 recordings |

## Requirements

- **Python:** 3.9 or higher
- **Platform:** Linux (tested on Raspberry Pi, Asahi Linux on Apple Silicon, Debian, Ubuntu, Fedora)
- **Architecture:** x86_64, ARM64, ARMv7 (platform-agnostic)
- **Package Manager:** apt, dnf, yum, pacman, or zypper (auto-detected)
- **Network:** Internet connection for KiwiSDR access
- **Storage:** ~5GB recommended for recordings

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Architecture, configuration, and usage guide
- **[INSTALL.md](INSTALL.md)** - Detailed installation and troubleshooting
- **[DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)** - Complete deployment record

## Code Quality

- ✅ Type hints throughout
- ✅ Comprehensive error handling
- ✅ Modern Python practices (no deprecated APIs)
- ✅ PEP 8 compliant
- ✅ Atomic file operations
- ✅ Proper logging framework

## Future Expansion

Frequency Harvester is designed for growth:
- Support for multiple frequencies
- Multiple broadcast types (news, weather, time signals)
- Configurable recording schedules per frequency
- Web interface for monitoring
- Multi-receiver redundancy

## License

MIT License - See [LICENSE](LICENSE) for details

## Acknowledgments

- Built with [Claude Code](https://claude.com/claude-code)
- Uses [KiwiSDR client](https://github.com/jks-prv/kiwiclient) by John Seamons
- Inspired by the global KiwiSDR community

---

**🤖 Generated with Claude Code**
