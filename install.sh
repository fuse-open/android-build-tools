#!/bin/bash

# This script will install the Android SDK and NDK, and tell Uno where they are found.
# Note that Java 8 (not 9) is required to install Android SDK.

SDK_VERSION="4333796"

# Begin script
SELF=`echo $0 | sed 's/\\\\/\\//g'`
cd "`dirname "$SELF"`" || exit 1

function fatal-error {
    echo -e "\nERROR: Install failed -- please read output for clues, or open an issue on GitHub." >&2
    echo -e "\nNote that Java 8 (not 9+) is required to install Android SDK." >&2
    exit 1
}

trap 'fatal-error' ERR

# Detect platform
case "$(uname -s)" in
Darwin)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-darwin-$SDK_VERSION.zip
    SDK_DIR=~/Library/Android/sdk
    ;;
Linux)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-linux-$SDK_VERSION.zip
    SDK_DIR=~/Android/Sdk
    ;;
CYGWIN*|MINGW*|MSYS*)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-windows-$SDK_VERSION.zip
    SDK_DIR=$LOCALAPPDATA\\Android\\sdk
    IS_WINDOWS=1
    ;;
*)
    echo "ERROR: Unsupported platform $(uname -s)" >&2
    exit 1
    ;;
esac

function native-path {
    if [ "$IS_WINDOWS" = 1 ]; then
        echo `echo $1 | sed 's/\\//\\\\/g'`
    else
        echo $1
    fi
}

NDK_DIR=`native-path $SDK_DIR/ndk-bundle`

# Detect JAVA_HOME on Windows
if [[ "$IS_WINDOWS" = 1 && -z "$JAVA_HOME" ]]; then
    IFS=$'\n'
    for exe in `where javac.exe 2>&1`; do
        if [ -f "$exe" ]; then
            version=`"$exe" -version 2>&1 | grep 1.8.`
            if [ -n "$version" ]; then
                dir=`dirname "$exe"`
                export JAVA_HOME=`dirname "$dir"`
                break
            fi
        fi
    done

    if [ -z "$JAVA_HOME" ]; then
        root=$PROGRAMFILES\\Java

        IFS=$'\n'
        for dir in `ls -1 "$root"`; do
            if [[ "$dir" == jdk1.8.* ]]; then
                export JAVA_HOME=$root\\$dir
                break
            fi
        done
    fi

    if [ -z "$JAVA_HOME" ]; then
        echo -e "ERROR: The JAVA_HOME variable is not set, and JDK8 was not found in PATH or '$root'." >&2
        echo -e "\nGet OpenJDK8 from https://adoptopenjdk.net/ and try again." >&2
        exit 1
    else
        echo "Found JDK8 at $JAVA_HOME"
    fi
fi

# Download SDK
function get-zip {
    local url=$1
    local dir=$2
    local zip=`basename "$2"`.zip
    rm -rf "$zip"

    if [ -d "$dir" ]; then
        echo "Have $dir -- skipping download"
        return
    fi

    echo "Downloading $url"
    curl -s -L "$url" -o "$zip" -S --retry 3 || fatal-error

    echo "Extracting to $dir"
    mkdir -p "$dir"
    unzip -q "$zip" -d "$dir" || fatal-error
    rm -rf "$zip"
}

get-zip "$SDK_URL" "$SDK_DIR"

# Avoid warning from sdkmanager
mkdir -p ~/.android
touch ~/.android/repositories.cfg

# Install packages
function sdkmanager {
    if [ "$IS_WINDOWS" = 1 ]; then
        "$SDK_DIR/tools/bin/sdkmanager.bat" "$@"
    else
        "$SDK_DIR/tools/bin/sdkmanager" "$@"
    fi
}

echo "Accepting licenses"
yes | sdkmanager --licenses > /dev/null

function sdkmanager-install {
    echo "Installing $1"
    yes | sdkmanager $1 > /dev/null
}

sdkmanager-install ndk-bundle
sdkmanager-install "cmake;3.6.4111459"

# Emit config file for Uno
# Backticks in .unoconfig can handle unescaped backslashes in Windows paths.
echo "Android.SDK.Directory: \`$SDK_DIR\`" > .unoconfig
echo "Android.NDK.Directory: \`$NDK_DIR\`" >> .unoconfig

if [ -n "$JAVA_HOME" ]; then
    echo "Java.JDK.Directory: \`$JAVA_HOME\`" >> .unoconfig
fi

echo -e "\n--- .unoconfig ----------------------------------------------------"
cat .unoconfig
echo      "-------------------------------------------------------------------"
