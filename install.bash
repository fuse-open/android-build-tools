# This script will install the Android SDK and NDK, and tell Uno where they are found.

SDK_VERSION="4333796"

# Begin script
SELF=`echo $0 | sed 's/\\\\/\\//g'`
cd "`dirname "$SELF"`" || exit 1

function fatal-error {
    echo -e "\nERROR: Install failed." >&2
    echo -e "\nPlease read output for clues, or open an issue on GitHub (https://github.com/mortend/android-build-tools/issues)." >&2
    echo -e "\nPlease note that JDK8 (not 9+) is required to install Android SDK. Get OpenJDK8 from https://adoptopenjdk.net/ and try again." >&2
    exit 1
}

trap 'fatal-error' ERR

# https://stackoverflow.com/a/13596664
nonascii() {
    LANG=C grep --color=always '[^ -~]\+';
}

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
        echo -e "\nPlease get OpenJDK8 from https://adoptopenjdk.net/ and try again." >&2
        exit 1
    else
        echo "Found JDK8 at $JAVA_HOME"
    fi
fi

# Download SDK
function download-error {
    echo -e "\nERROR: Download failed." >&2
    echo -e "\nPlease try again later, or open an issue on GitHub (https://github.com/mortend/android-build-tools/issues)." >&2
    exit 1
}

function get-zip {
    local url=$1
    local dir=$2
    local zip=`basename "$2"`.zip

    if [ -f "$zip" ]; then
        rm -rf "$dir" "$zip"
    elif [ -d "$dir" ]; then
        return
    fi

    echo "Downloading $url"
    curl -# -L "$url" -o "$zip" -S --retry 3 || download-error
    mkdir -p "$dir"
    unzip -q "$zip" -d "$dir" || download-error
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

function sdkmanager-silent {
    yes | sdkmanager "$@" > sdkmanager.log
    if [ $? != 0 ]; then
        cat sdkmanager.log
        fatal-error
    fi
}

echo "Accepting licenses"
sdkmanager-silent --licenses

function sdkmanager-install {
    echo "Installing $1"
    sdkmanager-silent $1
}

sdkmanager-install ndk-bundle
sdkmanager-install "cmake;3.6.4111459"

# Emit config file for Uno
node update-unoconfig.js \
    "Android.SDK.Directory: $SDK_DIR" \
    "Android.NDK.Directory: $NDK_DIR" \
    "Java.JDK.Directory: $JAVA_HOME"

echo -e "\n--- ~/.unoconfig --------------------------------------------------------------"
           cat ~/.unoconfig
echo -e   "-------------------------------------------------------------------------------\n"
