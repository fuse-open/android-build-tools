const fs = require("fs")
const path = require("path")
const os = require("os")
const jdkUtils = require("jdk-utils")
const mkdirp = require("mkdirp")
const touch = require("touch")
const rimraf = require("rimraf")
const Downloader = require("nodejs-file-downloader")
const decompress = require("decompress")
const {spawn} = require("child_process")
const prettyBytes = require("pretty-bytes")
const readline = require("readline")

// This script will install the Android SDK and tell Uno where it is found

const CMAKE_VERSION = "3.18.1"
const NDK_VERSION = "21.4.7075529"
const TOOLS_VERSION = "7583922"

function fatalError() {
    console.error("\nERROR: Install failed")
    console.error("\nPlease read output for clues or report the issue at https://github.com/fuse-open/android-build-tools/issues\n")
    process.exit(1)
}

process.on("uncaughtException", (err, origin) => {
    console.error(err, origin)
    fatalError()
})

/** Returns false if the string contains non-ASCII characters */
function isAscii(string) {
    for (let i = 0; i < string.length; i++) {
        const ch = string.charCodeAt(i)
        const ascii = ch >= 32 && ch < 127

        if (!ascii)
            return false
    }

    return true
}

/** Returns true if the string is falsy or empty */
function isNullOrEmpty(string) {
    return !string || !string.length
}

async function main() {
    let toolsUrl = undefined
    let sdkDir = undefined
    let isWindows = false

    // Detect platform
    switch (process.platform) {
        case "darwin": {
            toolsUrl = `https://dl.google.com/android/repository/commandlinetools-mac-${TOOLS_VERSION}_latest.zip`
            sdkDir = `${process.env.HOME}/Library/Android/sdk`
            break
        }
        case "linux": {
            toolsUrl = `https://dl.google.com/android/repository/commandlinetools-linux-${TOOLS_VERSION}_latest.zip`
            sdkDir = `${process.env.HOME}/Android/Sdk`
            break
        }
        case "win32": {
            toolsUrl = `https://dl.google.com/android/repository/commandlinetools-win-${TOOLS_VERSION}_latest.zip`
            sdkDir = `${process.env.LOCALAPPDATA}\\Android\\sdk`
            isWindows = true

            // We need a workaround for non-ASCII user names
            if (!isAscii(sdkDir)) {
                console.error(`WARNING: Android SDK cannot be installed in ${sdkDir}, because the SDK location cannot contain non-ASCII characters`)

                if (!isNullOrEmpty(process.env.PROGRAMDATA)) {
                    sdkDir = `${process.env.PROGRAMDATA}\\Android\\sdk`
                } else if (!isNullOrEmpty(process.env.SYSTEMDRIVE)) {
                    // We've seen $PROGRAMDATA being empty on some systems,
                    // so we need another fallback
                    sdkDir = `${process.env.SYSTEMDRIVE}\\ProgramData\\Android\\sdk`
                } else {
                    console.error("ERROR: Not able to detect Android SDK location")
                    process.exit(1)
                }

                console.log(`Changing SDK location to ${sdkDir}`)
            }

            break
        }
        default: {
            console.error(`ERROR: Unsupported platform ${process.platform}`)
            process.exit(1)
        }
    }

    const ndkDir = path.join(sdkDir, "ndk", NDK_VERSION)

    // Detect JAVA_HOME
    async function findJdkHome() {
        const runtimes = await jdkUtils.findRuntimes({checkJavac: true, withVersion: true, withTags: true})
        const result = getBestRuntime(runtimes.filter(rt => rt.hasJavac && rt.version && rt.version.major >= 11 && rt.version.major <= 19))

        if (result) {
            return result.homedir
        }
    }

    function getBestRuntime(runtimes) {
        const isJavaHomeEnv = runtimes.filter(rt => rt.isJavaHomeEnv)

        // Prefer JDK that is JAVA_HOME
        if (isJavaHomeEnv.length !== 0) {
            return isJavaHomeEnv[0]
        }

        const isInPathEnv = runtimes.filter(rt => rt.isInPathEnv)

        // Prefer JDK that is in PATH
        if (isInPathEnv.length !== 0) {
            return isInPathEnv[0]
        }

        const isAndroidStudio = runtimes.filter(rt => rt.homedir.includes("Android Studio"))

        // Prefer JDK that is included with Android Studio
        if (isAndroidStudio.length !== 0) {
            return isAndroidStudio[0]
        }

        if (runtimes.length !== 0) {
            // Prefer biggest major version
            runtimes.sort((a, b) => b.version.major - a.version.major)
            return runtimes[0]
        }
    }

    const javaHome = await findJdkHome()

    if (isNullOrEmpty(javaHome)) {
        jdkUtils.findRuntimes({checkJavac: true, withVersion: true, withTags: true}).then(console.log)
        console.error("\nERROR: JDK 11 or higher was not found")
        console.error("\nPlease get OpenJDK from https://adoptium.net/ and try again.\n")
        process.exit(1)
    }

    console.log(`Found JDK at ${javaHome}`)

    // Export JAVA_HOME for sdkmanager
    process.env.JAVA_HOME = javaHome

    // Make sure HOME is defined before invoking sdkmanager
    if (!isWindows && isNullOrEmpty(process.env.HOME)) {
        console.error("\nERROR: Your HOME variable is undefined")
        console.error("\nIf you're running with 'sudo', try running again from your user account without 'sudo'.")
        console.error("\nMore information: http://npm.github.io/installation-setup-docs/installing/a-note-on-permissions.html\n")
        process.exit(1)
    }

    // Download SDK
    function downloadError() {
        console.error("\nERROR: Download failed")
        console.error("\nPlease try again later or report the issue at https://github.com/fuse-open/android-build-tools/issues\n")
        process.exit(1)
    }

    function permissionError(destination) {
        const dirname = path.dirname(destination)

        console.error("\nERROR: Failed to create file or directory")
        console.error(`\nPlease make sure you have necessary permissions to write in "${dirname}".`)

        if (!isWindows) {
            // Reset permissions
            console.error(`\n    sudo chown -R \"$(whoami)\" \"${dirname}\"\n`)
        }

        process.exit(1)
    }

    async function getTools(url, sdkDir) {
        const dir = path.join(sdkDir, "cmdline-tools")
        const zip = path.join(sdkDir, "cmdline-tools.zip")

        if (fs.existsSync(zip)) {
            rimraf.sync(dir)
            rimraf.sync(zip)
        } else if (fs.existsSync(path.join(dir, "latest", "bin", "sdkmanager")) ||
                   fs.existsSync(path.join(dir, "latest", "bin", "sdkmanager.bat"))) {
            return
        }

        try {
            mkdirp.sync(path.join(dir, "temp"))
        } catch (err) {
            console.error(err)
            permissionError(path.join(dir, "temp"))
        }

        try {
            touch.sync(zip)
        } catch (err) {
            console.error(err)
            permissionError(zip)
        }

        console.log(`Downloading ${url}`)

        try {
            const downloader = new Downloader({
                url,
                directory: path.dirname(zip),
                onBeforeSave: (name) => path.basename(zip),
                onProgress: (percentage, chunk, remainingSize) => {
                    readline.cursorTo(process.stdout, 0, null)
                    process.stdout.write(`${percentage} % - ${prettyBytes(remainingSize)} remaining   `)
                },
                maxAttempts: 3,
                onError: (error) => {
                    console.error(error)
                },
            })

            await downloader.download()
            process.stdout.write("\n")
        } catch (err) {
            console.error(err)
            downloadError()
        }

        try {
            await decompress(zip, path.join(dir, "temp"))
        } catch (err) {
            console.error(err)
            downloadError()
        }

        // Move tools to the right location inside the SDK
        try {
            rimraf.sync(path.join(dir, "latest"))
            fs.renameSync(path.join(dir, "temp", "cmdline-tools"), path.join(dir, "latest"))
        } catch (err) {
            console.error(err)
            permissionError(path.join(dir, "latest"))
        }

        // Clean up
        rimraf.sync(zip)
        rimraf.sync(path.join(dir, "temp"))
    }

    await getTools(toolsUrl, sdkDir)

    // Avoid warning from sdkmanager
    try {
        mkdirp.sync(path.join(os.homedir(), ".android"))
        touch.sync(path.join(os.homedir(), ".android", "repositories.cfg"))
    } catch (err) {
        console.error(err)
    }

    // Install packages
    async function sdkmanager(args) {
        return new Promise((resolve, reject) => {
            const command = spawn(
                path.join(
                    sdkDir,
                    "cmdline-tools",
                    "latest",
                    "bin",
                    isWindows
                        ? "sdkmanager.bat"
                        : "sdkmanager"),
                args)

            // Type 'y' to accept licenses
            command.stdin.write("y\n")
            command.stdin.write("y\n")
            command.stdin.write("y\n")
            command.stdin.write("y\n")
            command.stdin.end()

            const lines = []

            command.stdout.on("data", output => {
                lines.push(output.toString())
            })

            command.on("exit", code => {
                const output = lines.join("\n").trim()

                // Verify that sdkmanager works (#9)
                if (output.includes("java.lang.NoClassDefFoundErrors")) {
                    console.error("\nERROR: Incompatible JDK version detected")
                    process.exit(1)
                }

                if (code === 0) {
                    resolve()
                } else {
                    console.log(output)
                    reject(`Exited with code ${code}`)
                }
            })
        })
    }

    console.log("Accepting licenses")
    await sdkmanager(["--licenses"])

    async function install(packages) {
        console.log(`Installing ${packages}`)
        await sdkmanager([packages])
    }

    await install(`cmake;${CMAKE_VERSION}`)
    await install(`ndk;${NDK_VERSION}`)

    // Emit config file for Uno
    function updateUnoconfig(filename, args) {
        const obj = {}

        for (let i = 0; i < args.length; i++) {
            const colon = args[i].indexOf(":")
            obj[args[i].substring(0, colon)] = args[i].substring(colon + 1).trim()
        }

        const lines = fs.existsSync(filename)
            ? fs.readFileSync(filename, "utf8").trim().split(/\n|\r\n/)
            : []

        for (key in obj) {
            // Remove old instances of ${key}
            for (let i = 0; i < lines.length; i++)
                if (lines[i] && lines[i].startsWith(key + ":"))
                    lines.splice(i--, 1)

            // Add new ${key}
            if (obj[key] && obj[key].length)
                if (obj[key].indexOf("\\") != -1)
                    lines.push(`${key}: \`${obj[key]}\``)
                else if (obj[key].indexOf(" ") != -1 ||
                        obj[key].indexOf(":") != -1)
                    lines.push(`${key}: "${obj[key]}"`)
                else
                    lines.push(`${key}: ${obj[key]}`)
        }

        fs.writeFileSync(filename, lines.join(os.EOL).trim() + os.EOL)
    }

    const unoconfig = path.join(os.homedir(), ".unoconfig")

    updateUnoconfig(unoconfig, [
        `Android.SDK.Directory: ${sdkDir}`,
        `Android.NDK.Directory: ${ndkDir}`,
        `Java.JDK.Directory: ${javaHome}`
    ])

    console.log()
    console.log("--- ~/.unoconfig --------------------------------------------------------------")
    console.log(fs.readFileSync(unoconfig).toString("utf8").trim())
    console.log("-------------------------------------------------------------------------------")
}

main().catch(reason => {
    console.error(reason)
    fatalError()
})
