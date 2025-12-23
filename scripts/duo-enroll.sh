#\!/usr/bin/env bash
# Duo Enrollment Helper Script
# Run this interactively to enroll in Duo

set -euo pipefail

RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
NC='\\033[0m'

echo -e "${GREEN}=== Duo Enrollment Helper ===${NC}"
echo

# Check if we're interactive
if [[ \! -t 0 ]] || [[ \! -t 1 ]]; then
    echo -e "${RED}ERROR: This script must be run interactively${NC}"
    echo "SSH into the machine and run this script directly"
    exit 1
fi

echo "This will trigger Duo enrollment for your user account."
echo
echo "What will happen:"
echo "  1. Duo will display an enrollment URL"
echo "  2. Open the URL in your browser"
echo "  3. Follow the steps to add Duo Mobile app"
echo "  4. After enrollment, sudo will use push notifications"
echo
read -p "Press Enter to continue..."

echo
echo -e "${YELLOW}Triggering sudo to start Duo enrollment...${NC}"
echo

# This will trigger the Duo enrollment prompt
sudo -k  # Clear cached credentials
sudo echo "Enrollment successful\! Duo is now configured."

echo
echo -e "${GREEN}=== Enrollment Complete ===${NC}"
echo "Future sudo commands will send a push notification to your phone."
