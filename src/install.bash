# This script will install the Android SDK and NDK, and tell Uno where they are found.

CMAKE_VERSION="3.18.1"
NDK_VERSION="21.4.7075529"
TOOLS_VERSION="7583922"

# Begin script.
SELF=`echo $0 | sed 's/\\\\/\\//g'`
cd "`dirname "$SELF"`" || exit 1

function fatal-error {
    echo -e "\nERROR: Install failed." >&2
    echo -e "\nPlease read output for clues, or open an issue on GitHub (https://github.com/fuse-open/android-build-tools/issues)." >&2
    echo -e "\nPlease note that JDK is required to install Android SDK. Get OpenJDK from https://adoptium.net/ and try again." >&2
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

# Detect JAVA_HOME on Windows.
if [[ "$IS_WINDOWS" = 1 && -z "$JAVA_HOME" ]]; then
    android_studio_jre=$PROGRAMFILES\\Android\\Android\ Studio\\jre
    java_root1=$PROGRAMFILES\\Eclipse\ Adoptium
    java_root2=$PROGRAMFILES\\Java

    # First, see if Android Studio has the JDK.
    if [ -f "$android_studio_jre\\bin\\java.exe" ]; then
        export JAVA_HOME=$android_studio_jre
    fi

    # Look for JDK in PATH.
    if [ -z "$JAVA_HOME" ]; then
        IFS=$'\n'
        for exe in `where javac.exe 2>&1`; do
            if [ -f "$exe" ]; then
                dir=`dirname "$exe"`
                export JAVA_HOME=`dirname "$dir"`
                break
            fi
        done
    fi

    # Look for JDK in PROGRAMFILES.
    if [ -z "$JAVA_HOME" ]; then
        IFS=$'\n'
        for dir in `ls -1 "$java_root1"`; do
            if [[ "$dir" == jdk* && -f "$java_root1/$dir/bin/javac.exe" ]]; then
                export JAVA_HOME=$java_root1\\$dir
                break
            fi
        done
    fi

    if [ -z "$JAVA_HOME" ]; then
        IFS=$'\n'
        for dir in `ls -1 "$java_root2"`; do
            if [[ "$dir" == jdk* && -f "$java_root2/$dir/bin/javac.exe" ]]; then
                export JAVA_HOME=$java_root2\\$dir
                break
            fi
        done
    fi

    if [ -z "$JAVA_HOME" ]; then
        echo -e "ERROR: The JAVA_HOME variable is not set, and JDK was not found in PATH or in the following locations:" >&2
        echo -e "    * $android_studio_jre" >&2
        echo -e "    * $java_root1" >&2
        echo -e "    * $java_root2" >&2
        echo -e "\nPlease get OpenJDK from https://adoptium.net/ and try again." >&2
        exit 1
    else
        echo "Found JDK at $JAVA_HOME"
    fi

# Detect JAVA_HOME on Mac.
elif [[ "$IS_MAC" = 1 && -z "$JAVA_HOME" ]]; then
    android_studio_jre=/Applications/Android\ Studio.app/Contents/jre/jdk/Contents/Home/jre

    if [ -f "$android_studio_jre/bin/java" ]; then
        export JAVA_HOME=$android_studio_jre
        echo "Found JDK at $JAVA_HOME"
    fi

# Detect JAVA_HOME on Linux.
elif [[ "$IS_LINUX" = 1 && -z "$JAVA_HOME" ]]; then
    android_studio_jre=/opt/android-studio/jre

    if [ -f "$android_studio_jre/bin/java" ]; then
        export JAVA_HOME=$android_studio_jre
        echo "Found JDK at $JAVA_HOME"
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
