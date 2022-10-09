const jdkUtils = require("jdk-utils")

jdkUtils.findRuntimes({checkJavac: true, withVersion: true, withTags: true}).then(console.log)
