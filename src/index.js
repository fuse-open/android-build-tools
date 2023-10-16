const fs = require("fs")
const path = require("path")
const os = require("os")
const jdkUtils = require("jdk-utils")
const Downloader = require("nodejs-file-downloader")
const {spawn} = require("child_process")
const prettyBytes = require("pretty-bytes")
const readline = require("readline")

// Config
const TOOLS_VERSION = "10406996"

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

// Detected config
let toolsUrl = undefined
let sdkDir = undefined
let isWindows = false

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

async function findJdkHome() {
    const runtimes = await jdkUtils.findRuntimes({checkJavac: true, withVersion: true, withTags: true})

    // Prefer JDK 17 or better (Gradle 8.x)
    const result = getBestRuntime(runtimes.filter(rt => rt.hasJavac && rt.version && rt.version.major >= 17))

    if (result) {
        return result.homedir
    }

    // Fallback to JDK 11 or better (Gradle 7.x)
    const result2 = getBestRuntime(runtimes.filter(rt => rt.hasJavac && rt.version && rt.version.major >= 11))

    if (result2) {
        console.error("WARNING: JDK 17 is recommended for Android development, but was not found. Some features will not work")
        return result2.homedir
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
}

async function printJdkLocations() {
    jdkUtils.findRuntimes({checkJavac: true, withVersion: true, withTags: true}).then(console.log)
}

async function download(url, destination) {
    console.log(`Downloading ${url}`)

    const downloader = new Downloader({
        url,
        directory: path.dirname(destination),
        onBeforeSave: (name) => path.basename(destination),
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
}

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

async function install(package, version) {
    console.log(`Installing ${package}@${version}`)
    await sdkmanager([`${package};${version}`])
}

function updateUnoconfig(filename, obj) {
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

module.exports = {
    isNullOrEmpty,
    toolsUrl,
    sdkDir,
    isWindows,
    findJdkHome,
    printJdkLocations,
    download,
    sdkmanager,
    install,
    updateUnoconfig,
}
