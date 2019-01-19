#!/bin/bash

# This script will install the Android SDK and NDK, and tell Uno where they are found.
# Note: JDK8 is required to install the Android SDK.

SDK_VERSION="4333796"

# Begin script
SELF=`echo $0 | sed 's/\\\\/\\//g'`
cd "`dirname "$SELF"`" || exit 1

function fatal-error {
    echo -e "\nERROR: Install failed -- please read output for clues, and try reinstalling."
    exit 1
}

trap 'fatal-error' ERR

# Detect platform
case "$(uname -s)" in
Darwin)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-darwin-$SDK_VERSION.zip
    ;;
Linux)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-linux-$SDK_VERSION.zip
    ;;
CYGWIN*|MINGW*|MSYS*)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-windows-$SDK_VERSION.zip
    IS_WINDOWS=1
    ;;
*)
    echo "ERROR: Unsupported platform $(uname -s)" >&2
    exit 1
    ;;
esac

# Detect JAVA_HOME on Windows
if [[ "$IS_WINDOWS" = 1 && -z "$JAVA_HOME" ]]; then
    root=$PROGRAMFILES/Java

    IFS=$'\n'
    for dir in `ls -1 "$root"`; do
        if [[ "$dir" == jdk1.8.* ]]; then
            export JAVA_HOME=$root/$dir
            echo "Found JDK8 at $JAVA_HOME"
            break
        fi
    done

    if [ -z "$JAVA_HOME" ]; then
        echo "ERROR: The JAVA_HOME variable is not set, and JDK8 was not found in '$root'." >&2
        fatal-error
    fi
fi

# Download SDK
function get-zip {
    url=$1
    dir=$2
    zip=$2.zip

    if [ -d $dir ]; then
        echo "Have $dir -- skipping download"
        return
    fi

    if [ -f $zip ]; then
        echo "Have $zip -- skipping download"
    else
        echo "Downloading $url"
        curl -s -L $url -o $zip
    fi

    echo "Extracting to $dir"
    unzip -q $zip -d $dir
}

SDK_DIR="android-sdk"
get-zip $SDK_URL $SDK_DIR

# Install packages
function sdkmanager {
    if [ "$IS_WINDOWS" = 1 ]; then
        $SDK_DIR/tools/bin/sdkmanager.bat "$@"
    else
        $SDK_DIR/tools/bin/sdkmanager "$@"
    fi
}

echo "Accepting licenses"
yes | sdkmanager --licenses > /dev/null

echo "Installing NDK"
yes | sdkmanager ndk-bundle > /dev/null

echo "Installing CMake"
yes | sdkmanager "cmake;3.6.4111459" > /dev/null

# Emit config file for Uno
echo "Android.SDK.Directory: $SDK_DIR" > .unoconfig
echo "Android.NDK.Directory: $SDK_DIR/ndk-bundle" >> .unoconfig

# Done.
echo "Done."
