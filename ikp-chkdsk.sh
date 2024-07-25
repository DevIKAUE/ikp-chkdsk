#!/bin/sh
# We want to make this script as shell-agnostic as possible
# Requires curl, grep, sed, paste, awk, date to work properly
VERSION=5

add_crontab_if_not_exists () {
    (crontab -l | grep -q $SCRIPTPATH) && echo '>> Warning: Crontab entry already exists, skipping.' && return

    # Add the crontab entry
    (crontab -l 2>/dev/null; echo "0 8,15,22 * * * $SCRIPTPATH") | crontab -
}

remove_crontab_if_exists () {
    (crontab -l | grep -v $SCRIPTPATH | crontab -) || echo '>> Warning: Crontab entry does not exist, skipping.'
}

uninstall () {
    echo "> Uninstalling chkdsk..."
    echo "> Deleting cron entry..."
    remove_crontab_if_exists
    echo "> Uninstallation complete!"
}

check_root () {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root!"
        exit 1
    fi
}

check_commands () {
    # Check if commands are available
    for varname in "$@"; do
        if command -v $varname >/dev/null; then
             echo ">> $varname is installed. Continuing with execution."
        else
            echo ">> ERROR: $varname is not installed. Please install $varname."
            exit 1
        fi
    done
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
    check_commands curl grep sed paste awk date
    prepare "$LOGDIR" "$TMPDIR"
    echo "> Adding cron entry..."
    add_crontab_if_not_exists
    echo "> Installation complete!"
}

main () {
    echo "> Checking requirements..."
    check_commands curl grep sed paste awk date
    echo "> Preparing disk check..."
    prepare "$LOGDIR" "$TMPDIR"
    echo "> Reporting variables..."
    info_variables \
        "SCRIPTDIR: $SCRIPTDIR" \
        "SCRIPTPATH: $SCRIPTPATH" \
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
        "DATADIR: $DATADIR"
    echo "> Starting disk check..."

    # /run/user/1000/doc: Operation not permitted
    DISK_CHECK=$(df --output=target,pcent 2>/dev/null | sed '1d;s/%//g' | awk '{print $1 " " $2}' | paste -sd ' ' -)

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
SCRIPTPATH="$SCRIPTDIR/$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
HOSTNAME=$(cat /etc/hostname 2>/dev/null || hostname)
PACKAGE="ikp-chkdsk"
CHECK_DATE=$(date '+%Y%m%d')
REPORT_BASE_URL=$(grep -o '^REPORT_BASE_URL=.*' .env | cut -d '=' -f2)
TOKEN=$(grep -o '^TOKEN=.*' .env | cut -d '=' -f2)
LOGDIR="$SCRIPTDIR/log/$PACKAGE/$CHECK_DATE"
LOGFILE="$LOGDIR/$PACKAGE.log"
TMPDIR="/tmp/$PACKAGE/$CHECK_DATE"
TMPCRONFILE="$TMPDIR/$PACKAGE.sh"

# Check for script arguments
if [ "$1" = "--install" ]; then
    install
elif [ "$1" = "--uninstall" ]; then
    uninstall "$LOGDIR"
else
    main
fi