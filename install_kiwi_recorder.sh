#!/usr/bin/env bash
#
# KiwiSDR Recorder - Complete Installation Script
#
# This script installs all components needed for automated KiwiSDR recording:
# - KiwiSDR client software
# - Python dependencies
# - Directory structure
# - Main recorder script
# - Configuration and verification
#
# Usage:
#   sudo bash install_kiwi_recorder.sh
#
# Or for non-interactive mode:
#   sudo bash install_kiwi_recorder.sh --auto
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_USER="${SUDO_USER:-pi}"
HOME_DIR="/home/${INSTALL_USER}"
KIWI_CLIENT_DIR="${HOME_DIR}/kiwiclient"
KIWI_CLIENT_REPO="https://github.com/jks-prv/kiwiclient.git"
RECORDER_SCRIPT="${HOME_DIR}/kiwi_recorder.py"
REQUIREMENTS="${HOME_DIR}/requirements.txt"
OUTPUT_DIR="${HOME_DIR}/share/198k"
SCAN_DIR="${HOME_DIR}/kiwi_scans"
LOG_FILE="${HOME_DIR}/Shipping_Forecast_SDR_Recordings.log"
OLD_SCRIPTS_DIR="${HOME_DIR}/old_scripts"

AUTO_MODE=false
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

confirm() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        return 0
    fi

    local prompt="$1"
    local response
    read -p "$prompt [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

preflight_checks() {
    log_info "Running pre-flight checks..."

    check_root

    # Check if running on Raspberry Pi
    if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        log_warning "This doesn't appear to be a Raspberry Pi"
        if ! confirm "Continue anyway?"; then
            log_error "Installation cancelled"
            exit 1
        fi
    fi

    # Check Python version
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed"
        exit 1
    fi

    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    log_info "Python version: ${PYTHON_VERSION}"

    if python3 -c 'import sys; exit(0 if sys.version_info >= (3, 9) else 1)'; then
        log_success "Python version is compatible (3.9+)"
    else
        log_error "Python 3.9 or higher is required (found ${PYTHON_VERSION})"
        exit 1
    fi

    # Check available disk space
    AVAILABLE_SPACE=$(df -BG "${HOME_DIR}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 5 ]]; then
        log_warning "Low disk space: ${AVAILABLE_SPACE}GB available"
        log_warning "At least 5GB recommended for recordings"
        if ! confirm "Continue anyway?"; then
            exit 1
        fi
    else
        log_success "Disk space check passed: ${AVAILABLE_SPACE}GB available"
    fi

    log_success "Pre-flight checks completed"
    echo
}

# ============================================================================
# System Dependencies
# ============================================================================

install_system_dependencies() {
    log_info "Installing system dependencies..."

    apt-get update -qq

    # Core dependencies for kiwiclient
    PACKAGES=(
        git
        python3-pip
        python3-numpy
        python3-scipy
        python3-requests
        sox
        libsox-fmt-mp3
    )

    log_info "Installing packages: ${PACKAGES[*]}"
    apt-get install -y "${PACKAGES[@]}"

    log_success "System dependencies installed"
    echo
}

# ============================================================================
# KiwiSDR Client Installation
# ============================================================================

install_kiwiclient() {
    log_info "Installing KiwiSDR client..."

    if [[ -d "$KIWI_CLIENT_DIR" ]]; then
        log_warning "KiwiSDR client directory already exists: ${KIWI_CLIENT_DIR}"
        if confirm "Remove and reinstall?"; then
            log_info "Backing up existing installation..."
            mv "$KIWI_CLIENT_DIR" "${KIWI_CLIENT_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        else
            log_info "Keeping existing installation"
            return 0
        fi
    fi

    log_info "Cloning KiwiSDR client repository..."
    sudo -u "$INSTALL_USER" git clone "$KIWI_CLIENT_REPO" "$KIWI_CLIENT_DIR"

    # Verify critical files exist
    if [[ ! -f "${KIWI_CLIENT_DIR}/kiwirecorder.py" ]]; then
        log_error "kiwirecorder.py not found after installation"
        exit 1
    fi

    # Make kiwirecorder executable
    chmod +x "${KIWI_CLIENT_DIR}/kiwirecorder.py"

    log_success "KiwiSDR client installed to ${KIWI_CLIENT_DIR}"
    echo
}

# ============================================================================
# Python Dependencies
# ============================================================================

install_python_dependencies() {
    log_info "Checking Python dependencies..."

    # Check if python3-requests is already installed
    if python3 -c "import requests" 2>/dev/null; then
        REQUESTS_VERSION=$(python3 -c "import requests; print(requests.__version__)")
        log_success "python3-requests already installed (version ${REQUESTS_VERSION})"
    else
        log_warning "python3-requests not found, installing via apt..."
        apt-get install -y python3-requests
    fi

    # Verify all required modules
    log_info "Verifying Python modules..."
    REQUIRED_MODULES=(
        "requests"
        "zoneinfo"
        "concurrent.futures"
        "argparse"
        "pathlib"
        "logging"
    )

    for module in "${REQUIRED_MODULES[@]}"; do
        if python3 -c "import ${module}" 2>/dev/null; then
            log_success "  ✓ ${module}"
        else
            log_error "  ✗ ${module} - MISSING"
            exit 1
        fi
    done

    log_success "All Python dependencies satisfied"
    echo
}

# ============================================================================
# Directory Structure
# ============================================================================

create_directories() {
    log_info "Creating directory structure..."

    DIRS=(
        "$OUTPUT_DIR"
        "$SCAN_DIR"
        "$OLD_SCRIPTS_DIR"
    )

    for dir in "${DIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating: ${dir}"
            sudo -u "$INSTALL_USER" mkdir -p "$dir"
        else
            log_info "Already exists: ${dir}"
        fi
    done

    # Create log file with proper permissions
    if [[ ! -f "$LOG_FILE" ]]; then
        sudo -u "$INSTALL_USER" touch "$LOG_FILE"
        log_success "Created log file: ${LOG_FILE}"
    fi

    log_success "Directory structure created"
    echo
}

# ============================================================================
# Recorder Script Installation
# ============================================================================

install_recorder_script() {
    log_info "Installing recorder script..."

    # Check if script exists in current directory
    if [[ ! -f "kiwi_recorder.py" ]]; then
        log_error "kiwi_recorder.py not found in current directory"
        log_error "Please run this script from the directory containing kiwi_recorder.py"
        exit 1
    fi

    # Backup existing script if present
    if [[ -f "$RECORDER_SCRIPT" ]]; then
        BACKUP_NAME="${RECORDER_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)"
        log_warning "Backing up existing script to ${BACKUP_NAME}"
        cp "$RECORDER_SCRIPT" "$BACKUP_NAME"
    fi

    # Copy script
    cp kiwi_recorder.py "$RECORDER_SCRIPT"
    chown "$INSTALL_USER:$INSTALL_USER" "$RECORDER_SCRIPT"
    chmod +x "$RECORDER_SCRIPT"

    # Copy requirements.txt
    if [[ -f "requirements.txt" ]]; then
        cp requirements.txt "$REQUIREMENTS"
        chown "$INSTALL_USER:$INSTALL_USER" "$REQUIREMENTS"
        log_success "Copied requirements.txt"
    fi

    log_success "Recorder script installed to ${RECORDER_SCRIPT}"
    echo
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    log_info "Verifying installation..."

    local all_good=true

    # Check kiwiclient
    if [[ -f "${KIWI_CLIENT_DIR}/kiwirecorder.py" ]]; then
        log_success "  ✓ KiwiSDR client installed"
    else
        log_error "  ✗ KiwiSDR client NOT found"
        all_good=false
    fi

    # Check recorder script
    if [[ -x "$RECORDER_SCRIPT" ]]; then
        log_success "  ✓ Recorder script installed and executable"
    else
        log_error "  ✗ Recorder script NOT found or not executable"
        all_good=false
    fi

    # Check directories
    for dir in "$OUTPUT_DIR" "$SCAN_DIR"; do
        if [[ -d "$dir" ]]; then
            log_success "  ✓ Directory exists: ${dir}"
        else
            log_error "  ✗ Directory missing: ${dir}"
            all_good=false
        fi
    done

    # Test recorder script
    log_info "Testing recorder script..."
    if sudo -u "$INSTALL_USER" python3 "$RECORDER_SCRIPT" --help &>/dev/null; then
        log_success "  ✓ Recorder script runs successfully"
    else
        log_error "  ✗ Recorder script failed to run"
        all_good=false
    fi

    # Test kiwiclient
    log_info "Testing KiwiSDR client..."
    if sudo -u "$INSTALL_USER" python3 "${KIWI_CLIENT_DIR}/kiwirecorder.py" --help &>/dev/null; then
        log_success "  ✓ KiwiSDR client runs successfully"
    else
        log_error "  ✗ KiwiSDR client failed to run"
        all_good=false
    fi

    echo
    if [[ "$all_good" == "true" ]]; then
        log_success "Installation verification PASSED"
        return 0
    else
        log_error "Installation verification FAILED"
        return 1
    fi
}

# ============================================================================
# Post-Installation Instructions
# ============================================================================

show_next_steps() {
    echo
    echo "============================================================================"
    log_success "Installation Complete!"
    echo "============================================================================"
    echo
    echo "Next steps:"
    echo
    echo "1. Test the feed command (creates empty feed if no recordings):"
    echo "   sudo -u ${INSTALL_USER} python3 ${RECORDER_SCRIPT} feed"
    echo
    echo "2. Run a scan to find the best KiwiSDR receivers (~1-2 minutes):"
    echo "   sudo -u ${INSTALL_USER} python3 ${RECORDER_SCRIPT} scan"
    echo
    echo "3. Test a recording (13 minutes, requires scan to complete first):"
    echo "   sudo -u ${INSTALL_USER} python3 ${RECORDER_SCRIPT} record"
    echo
    echo "4. Set up automated cron jobs:"
    echo "   sudo -u ${INSTALL_USER} python3 ${RECORDER_SCRIPT} setup"
    echo
    echo "============================================================================"
    echo "Installed components:"
    echo "  - Recorder script:  ${RECORDER_SCRIPT}"
    echo "  - KiwiSDR client:   ${KIWI_CLIENT_DIR}"
    echo "  - Output directory: ${OUTPUT_DIR}"
    echo "  - Scan directory:   ${SCAN_DIR}"
    echo "  - Log file:         ${LOG_FILE}"
    echo "============================================================================"
    echo
    echo "Documentation: ${HOME_DIR}/projects/recorder/CLAUDE.md"
    echo "View logs:     tail -f ${LOG_FILE}"
    echo "Check cron:    sudo -u ${INSTALL_USER} crontab -l"
    echo
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    clear
    echo "============================================================================"
    echo "          KiwiSDR Recorder - Complete Installation Script"
    echo "============================================================================"
    echo
    echo "This script will install:"
    echo "  - KiwiSDR client (from GitHub)"
    echo "  - System dependencies (sox, numpy, scipy, etc.)"
    echo "  - Python dependencies (requests, etc.)"
    echo "  - Recorder script and directory structure"
    echo
    echo "Installation location: ${HOME_DIR}"
    echo "Installation user:     ${INSTALL_USER}"
    echo

    if [[ "$AUTO_MODE" == "false" ]]; then
        if ! confirm "Proceed with installation?"; then
            log_error "Installation cancelled by user"
            exit 0
        fi
        echo
    fi

    # Run installation steps
    preflight_checks
    install_system_dependencies
    install_kiwiclient
    install_python_dependencies
    create_directories
    install_recorder_script

    # Verify everything works
    if verify_installation; then
        show_next_steps
        exit 0
    else
        echo
        log_error "Installation completed but verification failed"
        log_error "Please review the errors above and try again"
        exit 1
    fi
}

# ============================================================================
# Run Main
# ============================================================================

main "$@"
