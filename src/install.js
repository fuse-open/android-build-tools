const fs = require("fs")
const path = require("path")
const os = require("os")
const mkdirp = require("mkdirp")
const touch = require("touch")
const rimraf = require("rimraf")
const decompress = require("decompress")
const {
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
} = require(".")

// This script will install the Android SDK and tell Uno where it is found

const CMAKE_VERSION = "3.18.1"

process.on("uncaughtException", (err, origin) => {
    console.error(err, origin)
    console.error("\nERROR: Install failed")
    console.error("\nPlease read output for clues or report the issue at https://github.com/fuse-open/android-build-tools/issues\n")
    process.exit(1)
})

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

async function downloadTools() {
    const dir = path.join(sdkDir, "cmdline-tools")
    const zip = path.join(sdkDir, "cmdline-tools.zip")
    const latest = path.join(dir, "latest")
    const temp = path.join(dir, "temp")

    if (fs.existsSync(zip)) {
        rimraf.sync(dir)
        rimraf.sync(zip)
    } else if (fs.existsSync(path.join(latest, "bin", "sdkmanager")) ||
               fs.existsSync(path.join(latest, "bin", "sdkmanager.bat"))) {
        return
    }

    try {
        mkdirp.sync(temp)
    } catch (err) {
        console.error(err)
        permissionError(temp)
    }

    try {
        touch.sync(zip)
    } catch (err) {
        console.error(err)
        permissionError(zip)
    }

    try {
        await download(toolsUrl, zip)
        await decompress(zip, temp)
    } catch (err) {
        console.error(err)
        console.error("\nERROR: Download failed")
        console.error("\nPlease try again later or report the issue at https://github.com/fuse-open/android-build-tools/issues\n")
        process.exit(1)
    }

    // Move tools to the right location inside the SDK
    try {
        rimraf.sync(latest)
        fs.renameSync(path.join(temp, "cmdline-tools"), latest)
    } catch (err) {
        console.error(err)
        permissionError(latest)
    }

    // Clean up
    rimraf.sync(zip)
    rimraf.sync(temp)
}

async function main() {
    const javaHome = await findJdkHome()

    if (isNullOrEmpty(javaHome)) {
        printJdkLocations()
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

    await downloadTools()

    // Avoid warning from sdkmanager
    try {
        mkdirp.sync(path.join(os.homedir(), ".android"))
        touch.sync(path.join(os.homedir(), ".android", "repositories.cfg"))
    } catch (err) {
        console.error(err)
    }

    console.log("Accepting licenses")
    await sdkmanager(["--licenses"])
    await install("cmake", CMAKE_VERSION)

    // Emit config file for Uno
    const unoconfig = path.join(os.homedir(), ".unoconfig")

    updateUnoconfig(unoconfig, [
        `Android.SDK.Directory: ${sdkDir}`,
        `Java.JDK.Directory: ${javaHome}`
    ])

    console.log()
    console.log("--- ~/.unoconfig --------------------------------------------------------------")
    console.log(fs.readFileSync(unoconfig).toString("utf8").trim())
    console.log("-------------------------------------------------------------------------------")
}

main()
