# This script will install the Android SDK and NDK, and tell Uno where they are found.

CMAKE_VERSION="3.10.2.4988404"
NDK_VERSION="21.0.6113669"
SDK_VERSION="4333796"

# Begin script.
SELF=`echo $0 | sed 's/\\\\/\\//g'`
cd "`dirname "$SELF"`" || exit 1

function fatal-error {
    echo -e "\nERROR: Install failed." >&2
    echo -e "\nPlease read output for clues, or open an issue on GitHub (https://github.com/fuse-open/android-build-tools/issues)." >&2
    echo -e "\nPlease note that JDK8 (not 9+) is required to install Android SDK. Get OpenJDK8 from https://adoptopenjdk.net/ and try again." >&2
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
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-darwin-$SDK_VERSION.zip
    SDK_DIR=~/Library/Android/sdk
    IS_MAC=1
    ;;
Linux)
    SDK_URL=https://dl.google.com/android/repository/sdk-tools-linux-$SDK_VERSION.zip
    SDK_DIR=~/Android/Sdk
    IS_LINUX=1
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

NDK_DIR=`native-path $SDK_DIR/ndk/$NDK_VERSION`

# Detect JAVA_HOME on Windows.
if [[ "$IS_WINDOWS" = 1 && -z "$JAVA_HOME" ]]; then
    android_studio_jre=$PROGRAMFILES\\Android\\Android\ Studio\\jre
    java_root=$PROGRAMFILES\\Java

    # First, see if Android Studio has the JDK.
    if [ -f "$android_studio_jre\\bin\\java.exe" ]; then
        export JAVA_HOME=$android_studio_jre
    fi

    # Look for JDK in PATH.
    if [ -z "$JAVA_HOME" ]; then
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
    fi

    # Look for JDK in Program Files.
    if [ -z "$JAVA_HOME" ]; then
        IFS=$'\n'
        for dir in `ls -1 "$java_root"`; do
            if [[ "$dir" == jdk1.8.* ]]; then
                export JAVA_HOME=$java_root\\$dir
                break
            fi
        done
    fi

    if [ -z "$JAVA_HOME" ]; then
        echo -e "ERROR: The JAVA_HOME variable is not set, and JDK8 was not found in PATH or in the following locations:" >&2
        echo -e "    * $android_studio_jre" >&2
        echo -e "    * $java_root" >&2
        echo -e "\nPlease get OpenJDK8 from https://adoptopenjdk.net/ and try again." >&2
        exit 1
    else
        echo "Found JDK8 at $JAVA_HOME"
    fi

# Detect JAVA_HOME on Mac.
elif [[ "$IS_MAC" = 1 && -z "$JAVA_HOME" ]]; then
    android_studio_jre=/Applications/Android\ Studio.app/Contents/jre/jdk/Contents/Home/jre

    if [ -f "$android_studio_jre/bin/java" ]; then
        export JAVA_HOME=$android_studio_jre
        echo "Found JDK8 at $JAVA_HOME"
    fi

# Detect JAVA_HOME on Linux.
elif [[ "$IS_LINUX" = 1 && -z "$JAVA_HOME" ]]; then
    android_studio_jre=/opt/android-studio/jre

    if [ -f "$android_studio_jre/bin/java" ]; then
        export JAVA_HOME=$android_studio_jre
        echo "Found JDK8 at $JAVA_HOME"
    fi
fi

# Make sure HOME is defined before invoking sdkmanager.
if [[ "$IS_WINDOWS" != 1 && -z "$HOME" ]]; then
    echo -e "\nERROR: Your HOME variable is undefined." >&2
    echo -e "\nIf you're running with 'sudo', try running again from your user account without 'sudo'." >&2
    echo -e "\nMore information: http://npm.github.io/installation-setup-docs/installing/a-note-on-permissions.html.\n" >&2
    exit 1
fi

# Download SDK.
function download-error {
    echo -e "\nERROR: Download failed." >&2
    echo -e "\nPlease try again later, or open an issue on GitHub (https://github.com/fuse-open/android-build-tools/issues)." >&2
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

function get-zip {
    local url=$1
    local dir=$2
    local zip=$2.zip

    if [ -f "$zip" ]; then
        rm -rf "$dir" "$zip"
    elif [ -d "$dir" ]; then
        return
    fi

    mkdir -p "$dir" || permission-error "$dir"
    touch "$zip" || permission-error "$zip"

    echo "Downloading $url"
    curl -# -L "$url" -o "$zip" -S --retry 3 || download-error
    unzip -q "$zip" -d "$dir" || download-error
    rm -rf "$zip"
}

get-zip "$SDK_URL" "$SDK_DIR"

# Avoid warning from sdkmanager.
mkdir -p ~/.android || :
touch ~/.android/repositories.cfg || :

# Install packages.
function sdkmanager {
    if [ "$IS_WINDOWS" = 1 ]; then
        "$SDK_DIR/tools/bin/sdkmanager.bat" "$@"
    else
        "$SDK_DIR/tools/bin/sdkmanager" "$@"
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
        echo -e "\nPlease note that JDK8 (not 9+) is required to install Android SDK. Get OpenJDK8 from https://adoptopenjdk.net/ and try again." >&2
        exit 1
    fi
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
