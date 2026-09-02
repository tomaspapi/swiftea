<div align="center">
  <img src="Design/Swiftea-AppIcon-1024.png" alt="Swiftea app icon." width="112">
  <h1>Swiftea</h1>
  <p><strong>Control your Ember Mug from the Mac you’re already using.</strong></p>
  <p>Monitor your mug, set the temperature, and get notified when your drink is ready — without reaching for your phone.</p>

  <p>
    <a href="https://github.com/tomaspapi/swiftea/releases/latest"><img alt="Latest Swiftea release" src="https://img.shields.io/github/v/release/tomaspapi/swiftea?sort=semver&amp;label=release&amp;style=flat-square"></a>
    <a href="https://github.com/tomaspapi/swiftea/actions/workflows/ci.yml"><img alt="Continuous integration status" src="https://github.com/tomaspapi/swiftea/actions/workflows/ci.yml/badge.svg?branch=main&amp;event=push"></a>
    <img alt="Requires macOS 26 or newer" src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat-square">
    <a href="LICENSE"><img alt="License: 0BSD" src="https://img.shields.io/badge/license-0BSD-blue?style=flat-square"></a>
  </p>

  <p>
    <a href="https://github.com/tomaspapi/swiftea/releases/latest/download/Swiftea.zip"><strong>Download Swiftea</strong></a>
    &nbsp;·&nbsp;
    <a href="https://tomaspapi.github.io/swiftea/">Visit the website</a>
  </p>
</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/Swiftea-Screenshot-Dark.png">
    <source media="(prefers-color-scheme: light)" srcset="Design/Swiftea-Screenshot-Light.png">
    <img src="Design/Swiftea-Screenshot-Light.png" alt="Screenshot of Swiftea showing a connected mug, heating and temperature controls, saved mugs, and battery history." width="680">
  </picture>
</p>

Swiftea connects directly to an Ember Mug 2 over Bluetooth. From the main window or menu bar, you can set the temperature, check live mug status, and review recent history. Swiftea reconnects automatically and requires no account or cloud service for mug control.

Mug readings, saved mug details, and history remain on your Mac. Swiftea does not include developer-operated analytics, advertising, or telemetry.

> [!NOTE]
> Swiftea is an independent project. It is not affiliated with, sponsored by, authorized by, or endorsed by Ember Technologies, Inc.

## What Swiftea does

- Starts or stops heating and sets a target temperature in Celsius or Fahrenheit.
- Shows current temperature, battery, charging, connection state, and whether the mug appears empty.
- Keeps up to 30 days of battery and temperature history locally on your Mac.
- Reconnects eligible saved mugs after connection loss, Mac wake, or Bluetooth recovery.
- Provides native notifications and optional sounds for useful mug events.
- Works from the main window, the menu bar, or both, including an option to show the menu bar item only while a mug is active.
- Supports up to 3 connected mugs with per-mug names and remembered preferences.

## Download and compatibility

Swiftea requires macOS 26 or newer. It is developed and tested with Ember Mug 2, the only model Swiftea currently supports. Other Ember products have not been validated and should be treated as unsupported, even if Swiftea happens to detect them.

[Download the latest Swiftea release](https://github.com/tomaspapi/swiftea/releases/latest/download/Swiftea.zip), unzip it, move Swiftea to your Applications folder, and open it. Swiftea uses Sparkle for future update checks and installation.

Prebuilt releases provided by the maintainer are signed with Developer ID and notarized by Apple. Apple’s notarization service performs automated security and code-signing checks; notarization is not App Review or an endorsement of Swiftea.

Bluetooth behavior can vary by firmware and Mac. Swiftea may not work with every Ember Mug 2 firmware version or macOS Bluetooth setup.

## Privacy and safety

Swiftea controls heated consumer hardware. Keep the mug supervised and do not rely on software, Bluetooth, notifications, or automation as a safety system.

Read Swiftea’s [Privacy Policy](PRIVACY_POLICY.md), [Safety Notice](SAFETY_NOTICE.md), and [Terms of Use](TERMS_OF_USE.md) before using a maintainer-provided build.

## Build from source

To build Swiftea, you need:

- Xcode 26 or newer.
- Swift 6.3 or newer.
- XcodeGen only when changing `project.yml` or regenerating the Xcode project.

The canonical Xcode project is `Swiftea.xcodeproj`. Run the development build with:

```zsh
./script/build_and_run.sh
```

Run the Swift test suite with:

```zsh
swift test --scratch-path "${TMPDIR%/}/swiftea-swiftpm-build"
```

A locally built copy is not the same artifact as a maintainer-provided Developer ID-signed and notarized release.

## Project stewardship

Swiftea is a personal, maintainer-led project. Bug reports and suggestions are welcome, but external code contributions and pull requests are not accepted. Swiftea’s source code is released under the highly permissive Zero-Clause BSD (0BSD) License, so you are welcome to fork it, modify it, and use it for any purpose permitted by the license.

See [Contributing to Swiftea](CONTRIBUTING.md) for the project’s participation policy.

## Reports and security

- Use the [bug report form](https://github.com/tomaspapi/swiftea/issues/new?template=bug_report.yml) when something is not working as expected.
- Use the [feature request form](https://github.com/tomaspapi/swiftea/issues/new?template=feature_request.yml) to suggest an improvement.
- Follow the [Security Policy](SECURITY.md) for a suspected vulnerability. Do not post private device information, full serial numbers, logs, or local file paths in a public issue.

## License and acknowledgements

Swiftea’s source code is released under the [Zero-Clause BSD License (0BSD)](LICENSE).

Prebuilt copies distributed by the maintainer are also covered by Swiftea’s [Terms of Use](TERMS_OF_USE.md) and [Safety Notice](SAFETY_NOTICE.md). See [Acknowledgements](ACKNOWLEDGEMENTS.md) for included third-party software and public reference material.
