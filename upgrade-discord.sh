#!/bin/bash

echo "--- Upgrade Discord script by EDM115 ---"

# Ensure the script is ran as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo"
    echo "Exiting..."
    exit 1
fi

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--version) version="$2"; shift ;;
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

# Define variables and URLs based on build
case $build in
    "stable") appname="discord"; pname="Discord"; base_url="https://dl.discordapp.net/apps/linux/" ;;
    "ptb") appname="discord-ptb"; pname="DiscordPTB"; base_url="https://dl-ptb.discordapp.net/apps/linux/" ;;
    "canary") appname="discord-canary"; pname="DiscordCanary"; base_url="https://dl-canary.discordapp.net/apps/linux/" ;;
    *) echo "Invalid build. Use 'stable', 'ptb', or 'canary'"; exit 1 ;;
esac

# Ensure a user is specified as the script is run as root, see https://issues.chromium.org/issues/40480798
if [[ -z "$user" ]]; then
    echo "No user specified. Please specify a user with -u/--user."
    exit 1
fi
launchcommand="sudo -u $user bash -c \"'$appname'\""

# Handle versioning
if [[ -z "$version" ]]; then
    echo "No version specified, downloading latest version..."
    url="https://discord.com/api/download/$build?platform=linux&format=deb"
    dest="/tmp/$appname-latest.deb"
    version="latest"
else
    url="${base_url}${version}/${appname}-${version}.deb"
    dest="/tmp/$appname-$version.deb"
fi

# Download the file
echo "Downloading $appname from $url..."
wget --content-disposition --trust-server-names $url -O $dest

# Install the package
echo "Installing $appname..."
sudo apt-get install "$dest"

# Remove the installer
rm "$dest"

# If BetterDiscord is enabled, upgrade it
if [[ "$betterdiscord" == "true" ]]; then
    echo "Reappliying BetterDiscord..."
    eval "$launchcommand" > /tmp/discord_upgrade_output.log 2>&1 &

    # Monitor until "splashScreen.pageReady" appears
    tail -f /tmp/discord_upgrade_output.log | while read line; do
        if [[ "$line" == *"splashScreen.pageReady"* ]]; then
            sleep 8
            pgrep -i $pname | xargs -I {} kill -9 {}
            break
        fi
    done

    rm /tmp/discord_upgrade_output.log

    # Upgrade betterdiscordctl
    echo "Upgrading BetterDiscord..."
    sudo betterdiscordctl self-upgrade

    # Install BetterDiscord
    if [[ "$build" == "stable" ]]; then
        bdparams=""
    else
        bdparams="-f '$build'"
    fi
    bdcommand="sudo -u $user bash -c \"betterdiscordctl $bdparams install\""
    eval "$bdcommand"
    echo "Betterdiscord updated"
fi

echo "$appname updated to v.$version"
echo "Done !"

