# This script will install the Android SDK and NDK, and tell Uno where they are found.

CMAKE_VERSION="3.18.1"
NDK_VERSION="21.4.7075529"
TOOLS_VERSION="7583922"

# Begin script.
SELF=`echo $0 | sed 's/\\\\/\\//g'`
cd "`dirname "$SELF"`" || exit 1

function fatal-error {
    echo -e "\nERROR: Install failed." >&2
    echo -e "\nPlease read output for clues or report the issue at https://github.com/fuse-open/android-build-tools/issues\n" >&2
    exit 1
}

trap 'fatal-error' ERR

# https://stackoverflow.com/a/13596664
nonascii() {
    LANG=C grep --color=always '[^ -~]\+';
}

# Detect platform.
case "$(uname -s)" in
Darwin)
    TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-mac-${TOOLS_VERSION}_latest.zip
    SDK_DIR=~/Library/Android/sdk
    IS_MAC=1
    ;;
Linux)
    TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-linux-${TOOLS_VERSION}_latest.zip
    SDK_DIR=~/Android/Sdk
    IS_LINUX=1
    ;;
CYGWIN*|MINGW*|MSYS*)
    TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-win-${TOOLS_VERSION}_latest.zip
    SDK_DIR=$LOCALAPPDATA\\Android\\sdk
    IS_WINDOWS=1

    # We need a workaround for non-ASCII user names.
    if [ -n "`echo "$SDK_DIR" | nonascii`" ]; then
        echo -e "\nWARNING: Android SDK cannot be installed in $SDK_DIR, because the SDK location cannot contain non-ASCII characters." >&2
        if [ -n "$PROGRAMDATA" ]; then
            SDK_DIR=$PROGRAMDATA\\Android\\sdk
        else
            # We've seen $PROGRAMDATA being empty on some systems,
            # so we need another fallback.
            SDK_DIR=$SYSTEMDRIVE\\ProgramData\\Android\\sdk
        fi
        echo -e "\nChanging SDK location to $SDK_DIR." >&2
    fi
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

NDK_DIR=`native-path $SDK_DIR/ndk/$NDK_VERSION`

# Detect JAVA_HOME.
export JAVA_HOME=`node find-jdk.js`

if [ -z "$JAVA_HOME" ]; then
    node ls-jdk.js || :
    echo -e "\nERROR: JDK 11 or higher was not found." >&2
    echo -e "\nPlease get OpenJDK from https://adoptium.net/ and try again.\n" >&2
    exit 1
else
    echo "Found JDK at $JAVA_HOME"
fi

# Make sure HOME is defined before invoking sdkmanager.
if [[ "$IS_WINDOWS" != 1 && -z "$HOME" ]]; then
    echo -e "\nERROR: Your HOME variable is undefined." >&2
    echo -e "\nIf you're running with 'sudo', try running again from your user account without 'sudo'." >&2
    echo -e "\nMore information: http://npm.github.io/installation-setup-docs/installing/a-note-on-permissions.html\n" >&2
    exit 1
fi

# Download SDK.
function download-error {
    echo -e "\nERROR: Download failed." >&2
    echo -e "\nPlease try again later or report the issue at https://github.com/fuse-open/android-build-tools/issues\n" >&2
    exit 1
}

function permission-error {
    echo -e "\nERROR: Failed to create file or directory." >&2
    echo -e "\nPlease make sure you have necessary permissions to write in '`dirname "$1"`'." >&2
    if [ "$IS_WINDOWS" != 1 ]; then
        # Reset permissions.
        echo -e "\n    sudo chown -R \"$(whoami)\" \"`dirname "$1"`\"\n" >&2
    fi
    exit 1
}

function get-tools {
    local url=$1
    local dir=$2/cmdline-tools
    local zip=$2/cmdline-tools.zip

    if [ -f "$zip" ]; then
        rm -rf "$dir" "$zip"
    elif [[ -f "$dir/latest/bin/sdkmanager" || -f "$dir/latest/bin/sdkmanager.bat" ]]; then
        return
    fi

    mkdir -p "$dir/temp" || permission-error "$dir/temp"
    touch "$zip" || permission-error "$zip"

    echo "Downloading $url"
    curl -# -L "$url" -o "$zip" -S --retry 3 || download-error
    unzip -q "$zip" -d "$dir/temp" || download-error

    # Move tools to right location inside SDK
    rm -rf "$dir/latest" || permission-error "$dir/latest"
    mv "$dir/temp/cmdline-tools" "$dir/latest" || permission-error "$dir/latest"

    # Clean up
    rm -rf "$zip" "$dir/temp"
}

get-tools "$TOOLS_URL" "$SDK_DIR"

# Avoid warning from sdkmanager.
mkdir -p ~/.android || :
touch ~/.android/repositories.cfg || :

# Install packages.
function sdkmanager {
    if [ "$IS_WINDOWS" = 1 ]; then
        "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager.bat" "$@"
    else
        "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" "$@"
    fi
}

function sdkmanager-silent {
    yes | sdkmanager "$@" > ~/.android/sdkmanager.log
    if [ $? != 0 ]; then
        cat ~/.android/sdkmanager.log
        fatal-error
    fi

    # Verify that sdkmanager works (#9).
    cat ~/.android/sdkmanager.log | grep java.lang.NoClassDefFoundErrors

    if [ $? == 0 ]; then
        echo -e "\nERROR: Incompatible JDK version detected." >&2
        exit 1
    fi

    rm ~/.android/sdkmanager.log
}

echo "Accepting licenses"
sdkmanager-silent --licenses

function sdkmanager-install {
    echo "Installing $1"
    sdkmanager-silent $1
}

sdkmanager-install "cmake;$CMAKE_VERSION"
sdkmanager-install "ndk;$NDK_VERSION"

# Emit config file for Uno.
node update-unoconfig.js \
    "Android.SDK.Directory: $SDK_DIR" \
    "Android.NDK.Directory: $NDK_DIR" \
    "Java.JDK.Directory: $JAVA_HOME"

echo -e "\n--- ~/.unoconfig --------------------------------------------------------------"
           cat ~/.unoconfig
echo -e   "-------------------------------------------------------------------------------\n"
