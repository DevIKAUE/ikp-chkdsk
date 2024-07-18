#!/bin/sh
# We want to make this script as shell-agnostic as possible
# Requires 'curl' to work properly

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

check_updates() {
    # :param $1 is the UPDATE_URL
    # :param $2 is the PACKAGE_URL
    # :param $3 is the TMPCRONFILE
    # :param $4 is the TMPUPDATEFILE
    # :param $5 is the TMPDIR
    # :param $6 is the CRONFILE
    # Assuming current_version and cronfile are defined elsewhere
    echo "> Downloading update file from '$1'..."
    wget -qO "$4" "$1"

    echo "> Checking for newer versions... (current version: $VERSION)"
    # Check if CRONFILE exists
    if [ -f "$6" ]; then
        # Fetch the update and grep to extract the version
        NEW_VERSION=$(cat "$4")

        if [ -z "$NEW_VERSION" ]; then
            echo "> Unable to find VERSION in the update."
            return
        fi

        # Compare versions
        if [ "$NEW_VERSION" -gt "$VERSION" ]; then
            echo "> A new version is available: $NEW_VERSION. Updating..."
            wget -qO "$3" "$2"
            mv "$3" "$6"
            echo "$NEW_VERSION" > "$DATADIR/VERSION"
            echo "> Update completed."
        else
            echo "> You are up to date. Current version: $VERSION."
        fi
    else
        echo "> Data file $6 not found."
    fi

    # Remove tmpdir
    rm -r "$5"
}

install () {
    echo "> Installing chkdsk..."
    check_root
    check_curl
    prepare "$LOGDIR" "$DATADIR" "$TMPDIR"
    echo "$VERSION" > "$DATADIR/VERSION"
    wget -qO "$CRONFILE" "$PACKAGE_URL"
    echo "> Installation complete!"
}

main () {
    echo "> Checking for permissions..."
    check_root
    echo "> Checking requirements..."
    check_curl
    echo "> Checking for updates..."
    check_updates "$UPDATE_URL" "$PACKAGE_URL" "$TMPCRONFILE" "$TMPUPDATEFILE" "$TMPDIR" "$CRONFILE"
    echo "> Preparing disk check..."
    prepare "$LOGDIR" "$DATADIR" "$TMPDIR"
    echo "> Reporting variables..."
    info_variables \
        "SCRIPTDIR: $SCRIPTDIR" \
        "HOSTNAME: $HOSTNAME" \
        "VERSION: $VERSION" \
        "PACKAGE: $PACKAGE" \
        "CHECK_DATE: $CHECK_DATE" \
        "UPDATE_URL: $UPDATE_URL" \
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
HOSTNAME=$(cat /etc/hostname)
PACKAGE="ikp-chkdsk"
CHECK_DATE=$(date '+%Y%m%d')
UPDATE_URL=$(grep -o '^UPDATE_URL=.*' .env | cut -d '=' -f2)
PACKAGE_URL=$(grep -o '^PACKAGE_URL=.*' .env | cut -d '=' -f2)
REPORT_BASE_URL=$(grep -o '^REPORT_BASE_URL=.*' .env | cut -d '=' -f2)
TOKEN=$(grep -o '^TOKEN=.*' .env | cut -d '=' -f2)
LOGDIR="/var/log/$PACKAGE/$CHECK_DATE"
LOGFILE="$LOGDIR/$PACKAGE.log"
TMPDIR="/tmp/$PACKAGE/$CHECK_DATE"
TMPCRONFILE="$TMPDIR/$PACKAGE.sh"
TMPUPDATEFILE="$TMPDIR/VERSION"
CRONFILE="/etc/cron.daily/$PACKAGE"
DATADIR="/etc/$PACKAGE"
VERSION=$(cat "$SCRIPTDIR"/VERSION 2>/dev/null || cat "$DATADIR"/VERSION 2>/dev/null || echo "0")

# Check for script arguments
if [ "$1" = "--install" ]; then
    install
elif [ "$1" = "--uninstall" ]; then
    uninstall "$LOGDIR" "$DATADIR" "$CRONFILE"
else
    main
fi