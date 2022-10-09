const jdkUtils = require("jdk-utils")

jdkUtils.findRuntimes({checkJavac: true, withVersion: true, withTags: true}).then(
    runtimes => {
        // Prefer JDK 11 for Android Development
        let result = getBestRuntime(runtimes.filter(rt => rt.hasJavac && rt.version && rt.version.major === 11))

        if (!result) {
            // See if a higher JDK version is available
            result = getBestRuntime(runtimes.filter(rt => rt.hasJavac && rt.version && rt.version.major > 11))
        }

        if (result) {
            console.log(result.homedir)
        }
    }
)

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

    if (runtimes.length !== 0) {
        return runtimes[0]
    }
}
