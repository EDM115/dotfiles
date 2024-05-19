#!/bin/bash

echo "--- Launch Discord script by EDM115 ---"

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -b|--build) build="$2"; shift ;;
        -bd|--betterdiscord) betterdiscord="$2"; shift ;;
        -u|--user) user="$2"; shift ;;
        *) echo "Unknown parameter passed : $1"; exit 1 ;;
    esac
    shift
done

# Validate build parameter
if [[ -z "$build" ]]; then
    echo "Build not provided. Usage : -b/--build [stable|ptb|canary]"
    echo "Exiting..."
    exit 1
fi

# Define variables based on build
case $build in
    "stable") appname="discord"; pname="Discord" ;;
    "ptb") appname="discord-ptb"; pname="DiscordPTB" ;;
    "canary") appname="discord-canary"; pname="DiscordCanary" ;;
    *) echo "Invalid build. Use 'stable', 'ptb', or 'canary'"; exit 1 ;;
esac

# Determine how to launch the app based on whether it's run as root
if [[ $EUID -eq 0 ]]; then
    # Check if user is set when script is run as root
    if [[ -z "$user" ]]; then
        echo "No user specified. Use -u/--user to specify a user."
        exit 1
    fi
    launchcommand="sudo -u $user bash -c \"'$appname'\""
else
    # Use the current user to run the app
    user="$(whoami)"
    launchcommand="$appname"
fi

# Launch discord and capture stdout
eval "$launchcommand" | while read line
do
    echo "$line"

    # Check for the update-manually message
    if [[ "$line" == *"update-manually"* ]]; then
        # Extract version from the line
        version=$(echo "$line" | grep -oP 'update-manually \K[0-9.]+')

        # Kill discord
        pgrep -i $pname | xargs -I {} kill -9 {}
        sleep 2

        # Call updater script with the new version and restart discord
        sudo ~/upgrade-discord.sh -v $version -b $build -bd $betterdiscord -u $user | while read update_line
        do
            if [[ "$update_line" == *"Done !"* ]]; then
                eval "$launchcommand" &
                break 2
            fi
        done

        break
    fi

    # Check for the splashScreen.pageReady message (no update)
    if [[ "$line" == *"splashScreen.pageReady"* ]]; then
        pgrep -i $pname | xargs -I {} kill -9 {}
        nohup bash -c "$launchcommand" >/dev/null 2>&1 &
        break
    fi
done

