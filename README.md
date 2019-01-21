# Android build tools installer

[![AppVeyor build status](https://img.shields.io/appveyor/ci/mortend/android-build-tools/master.svg?logo=appveyor&style=flat-square)](https://ci.appveyor.com/project/mortend/android-build-tools/branch/master)
[![Travis CI build status](https://img.shields.io/travis/mortend/android-build-tools/master.svg?style=flat-square)](https://travis-ci.org/mortend/android-build-tools)
[![NPM package](https://img.shields.io/npm/v/android-build-tools.svg?style=flat-square)](https://www.npmjs.com/package/android-build-tools)
[![License: MIT](https://img.shields.io/github/license/fuse-open/uno.svg?style=flat-square)](LICENSE)

Android SDK and NDK installer for Uno and Fuse apps, suitable for installing on Linux, macOS and Windows (64-bit).

## Install

```
npm install android-build-tools -g
```

Please note that [Java 8 (not 9+) is required](https://stackoverflow.com/questions/46402772/failed-to-install-android-sdk-java-lang-noclassdeffounderror-javax-xml-bind-a) to install Android SDK, and that `bash` is required to run the install script. Bash is included in Git for Windows.

The SDK is installed to one of the locations below. The installer will only download the SDK or additional components when something is missing.

| Host OS  | Location                      |
|:---------|:------------------------------|
| Linux    | `~/Android/Sdk`               |
| macOS    | `~/Library/Android/sdk`       |
| Windows  | `%LOCALAPPDATA%\Android\sdk`  |

## Contributing

Please [report an issue](https://github.com/mortend/android-build-tools/issues) if you encounter a problem, or [open a pull request](https://github.com/mortend/android-build-tools/pulls) if you make a patch.
