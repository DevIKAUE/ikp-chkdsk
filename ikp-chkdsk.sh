#!/bin/sh
# We want to make this script as shell-agnostic as possible
# Requires 'curl' to work properly
VERSION=4

uninstall () {
    # :param $1 is the log directory
    # :param $2 is the chkdsk directory
    # :param $3 is the CRONFILE
    echo "> Uninstalling chkdsk..."
    check_root
    echo "> Deleting log directory..."
    rm -rf "$1"
    echo "> Deleting chkdsk..."
    rm -rf "$2"
    echo "> Deleting cronfile..."
    rm -rf "$3"
    echo "> Uninstallation complete!"
}

check_root () {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root!"
        exit 1
    fi
}

check_curl () {
    if command -v curl >/dev/null; then
        echo "curl is installed. Continuing with execution."
    else
        echo "WARN: curl is not installed. Please install curl."
    fi
}

prepare () {
    # :param $1 is the LOGDIR directory
    # :param $2 is the DATADIR directory
    # :param $3 is the TMPDIR directory

    # Create directories for every variable
    for varname in "$@"; do
        mkdir -p "$varname"
    done

    ### LOGGING ###
    mkdir -p "$1"/failed
    mkdir -p "$1"/success

    # Remove leftovers
    rm -rf "$1"/*.txt
    ### END LOGGING ###
}

info_variables() {
    for varname in "$@"; do
        echo "$varname"
    done
}

create_json() {
    # Construct JSON dynamically from variables
    DATA_JSON="{"
    for varname in "$@"; do
        key=$(echo $varname | cut -d ':' -f 1)
        value=$(echo $varname | cut -d ':' -f 2-)
        DATA_JSON="$DATA_JSON\"$key\": \"$value\","
    done
    DATA_JSON="${DATA_JSON%,}}"
    echo $DATA_JSON
}

install () {
    echo "> Installing chkdsk..."
    check_root
    check_curl
    prepare "$LOGDIR" "$DATADIR" "$TMPDIR"
    wget -qO "$CRONFILE" "$PACKAGE_URL"
    echo "> Installation complete!"
}

main () {
    echo "> Checking for permissions..."
    check_root
    echo "> Checking requirements..."
    check_curl
    echo "> Preparing disk check..."
    prepare "$LOGDIR" "$DATADIR" "$TMPDIR"
    echo "> Reporting variables..."
    info_variables \
        "SCRIPTDIR: $SCRIPTDIR" \
        "HOSTNAME: $HOSTNAME" \
        "VERSION: $VERSION" \
        "PACKAGE: $PACKAGE" \
        "CHECK_DATE: $CHECK_DATE" \
        "REPORT_BASE_URL: $REPORT_BASE_URL" \
        "TOKEN: $TOKEN" \
        "LOGDIR: $LOGDIR" \
        "LOGFILE: $LOGFILE" \
        "TMPDIR: $TMPDIR" \
        "TMPFILE: $TMPCRONFILE" \
        "CRONFILE: $CRONFILE" \
        "DATADIR: $DATADIR"
    echo "> Starting disk check..."
    DISK_CHECK=$(df --output=pcent -k / -k /home/ | sed '1d;s/[^0-9]//g' | paste -sd ' ' -)
    echo "> Status..."
    echo "$DISK_CHECK"
    echo "> Reporting to $REPORT_BASE_URL..."
    JSON_BODY=$(create_json \
        "hostname: $HOSTNAME" \
        "version: $VERSION" \
        "check_date: $CHECK_DATE" \
        "disk_check: $DISK_CHECK")
    curl -X POST -H "Content-Type: application/json" -u "$TOKEN" -d "$JSON_BODY" "$REPORT_BASE_URL"
    echo ""
    echo "> Done!"
}

# Variables
SCRIPTDIR="$( cd "$( dirname "$0" )" && pwd )"
HOSTNAME=$(cat /etc/hostname 2>/dev/null || hostname)
PACKAGE="ikp-chkdsk"
CHECK_DATE=$(date '+%Y%m%d')
PACKAGE_URL=$(grep -o '^PACKAGE_URL=.*' .env | cut -d '=' -f2)
REPORT_BASE_URL=$(grep -o '^REPORT_BASE_URL=.*' .env | cut -d '=' -f2)
TOKEN=$(grep -o '^TOKEN=.*' .env | cut -d '=' -f2)
LOGDIR="/var/log/$PACKAGE/$CHECK_DATE"
LOGFILE="$LOGDIR/$PACKAGE.log"
TMPDIR="/tmp/$PACKAGE/$CHECK_DATE"
TMPCRONFILE="$TMPDIR/$PACKAGE.sh"
CRONFILE="/etc/cron.daily/$PACKAGE"
DATADIR="/etc/$PACKAGE"

# Check for script arguments
if [ "$1" = "--install" ]; then
    install
elif [ "$1" = "--uninstall" ]; then
    uninstall "$LOGDIR" "$DATADIR" "$CRONFILE"
else
    main
fi