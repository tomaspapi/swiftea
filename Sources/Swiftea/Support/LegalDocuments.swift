import Foundation

struct SwifteaLegalSection: Identifiable {
    let id: String
    let title: String
    let body: String

    init(_ title: String, body: String) {
        self.id = title
        self.title = title
        self.body = body
    }
}

struct SwifteaLegalDocument {
    let title: String
    let summary: String
    let metadata: String
    let sections: [SwifteaLegalSection]
}

enum SwifteaLegalDocuments {
    static let currentTermsVersion = "1.0"
    static let currentSafetyNoticeVersion = "1.0"
    static let effectiveDate = "July 18, 2026"

    static let termsOfUse = SwifteaLegalDocument(
        title: "Terms of Use",
        summary: "These terms explain the conditions for using a prebuilt copy of Swiftea distributed by the Developer with a compatible Ember Mug. Please read them together with the Safety Notice.",
        metadata: "Version \(currentTermsVersion) · Effective \(effectiveDate)",
        sections: [
            SwifteaLegalSection(
                "1. Agreement",
                body: "These Terms of Use are an agreement between you and Tomás Papi, Swiftea’s independent developer and maintainer (the “Developer”). They apply to prebuilt copies of Swiftea distributed by the Developer. By selecting the agreement checkbox and using Swiftea, you confirm that you have read, understood, and agreed to these terms and the Safety Notice. Sections 5–7 and 11–13 are especially important: they explain risks of severe harm, software and Bluetooth limitations, your safety responsibilities, warranty disclaimers, an assumption of risk, a release of certain claims (including certain ordinary-negligence claims), and limits on liability. Each of those provisions applies only to the extent permitted by law. If you do not agree, do not use Swiftea."
            ),
            SwifteaLegalSection(
                "2. Open-source license",
                body: "Swiftea’s source code is offered under the Zero-Clause BSD License (0BSD). That license governs permission to use, copy, modify, and distribute the source code. These terms do not take away rights granted by 0BSD. They address prebuilt copies distributed by the Developer, their interaction with physical hardware, and the related safety and liability terms to the extent permitted by law. A modified or independently distributed build is the responsibility of whoever creates or distributes it."
            ),
            SwifteaLegalSection(
                "3. Unofficial, independent software",
                body: "Swiftea is an independent project. It is not affiliated with, sponsored by, authorized by, or endorsed by Ember Technologies, Inc. Ember, Ember Mug, Ember Mug 2, and related names and marks belong to their respective owners. The Developer does not manufacture, sell, warrant, repair, or control the mug, charging coaster, firmware, battery, or other Ember products."
            ),
            SwifteaLegalSection(
                "4. Intended use and eligibility",
                body: "Swiftea is a personal utility for controlling a compatible Ember Mug that you own or are authorized to use. It is not a safety system, medical device, commercial temperature-control system, or substitute for supervising hot liquids and electrical products. You must be legally able to enter this agreement. If you are not an adult under the law where you live, a parent or legal guardian must review and accept these terms for you."
            ),
            SwifteaLegalSection(
                "5. Heated-hardware risks",
                body: "An Ember Mug contains a heating element, hot liquid, a rechargeable battery, electronics, and charging equipment. Using it can involve burns, spills, overheating, fire, electrical hazards, property damage, battery failure, serious bodily injury, or death, as well as damage to the mug and nearby objects. Do not use Swiftea or a heated mug unattended, while sleeping, near flammable materials, or in any situation where a delayed or failed shutoff could cause harm. Keep children and pets appropriately supervised. Always follow Ember’s current manuals, warnings, care instructions, safety notices, and recalls."
            ),
            SwifteaLegalSection(
                "6. Software and Bluetooth limitations",
                body: "Swiftea is unofficial software and may contain bugs, defects, coding errors, omissions, or unintended behavior. It may send a delayed, repeated, incorrect, or unintended command; fail to send or stop a command; misread or misreport the mug’s state; or affect the mug in a way the Developer did not foresee. These events can occur even when you use Swiftea correctly and follow every instruction. Bluetooth can also fail, disconnect, reconnect, lag, or be interrupted by another app, another device, macOS sleep, radio interference, firmware behavior, or hardware conditions. Automatic shutoff, automatic reconnection, notifications, history, and other automation may fail. Never rely on Swiftea to prevent burns, serious bodily injury, death, fire, property damage, or any other unsafe condition."
            ),
            SwifteaLegalSection(
                "7. Your responsibilities",
                body: "You are responsible for checking the physical mug and its surroundings, choosing a safe target temperature, and confirming that heating and charging behave as expected. Stop using and disconnect the mug if it is damaged, leaking, unusually hot, smoking, producing an unusual smell, behaving unexpectedly, or showing a state that conflicts with Swiftea. Never microwave an Ember Mug. Dry it completely before placing it on a charging coaster, and use compatible official charging equipment as directed by Ember. Do not use Swiftea for unlawful, hazardous, abusive, or safety-critical purposes."
            ),
            SwifteaLegalSection(
                "8. Multiple controllers and account security",
                body: "An Ember Mug generally accepts one active controller at a time. Close other apps that may control the same mug before using Swiftea. You are responsible for access to your Mac and for changes made through Swiftea while your user account is open."
            ),
            SwifteaLegalSection(
                "9. Local data and update checks",
                body: "Swiftea does not require an account and does not include developer-operated analytics or telemetry. It stores preferences, saved mug details, and limited mug history locally on your Mac. When update checks are enabled or started manually, Sparkle contacts Swiftea’s public update feed and may contact GitHub-hosted release infrastructure. Those third parties may receive ordinary network information such as your IP address and request metadata under their own policies. You are responsible for backing up or deleting local app data if that matters to you."
            ),
            SwifteaLegalSection(
                "10. Updates, availability, and support",
                body: "Swiftea may change, stop supporting a macOS version or mug behavior, or be discontinued at any time. Updates may add, remove, or change features. The Developer does not promise continuous availability, compatibility, security updates, bug fixes, support, or recovery of local data. You may stop using Swiftea at any time."
            ),
            SwifteaLegalSection(
                "11. No warranties",
                body: "TO THE FULLEST EXTENT PERMITTED BY LAW, SWIFTEA IS PROVIDED “AS IS” AND “AS AVAILABLE”, WITHOUT WARRANTIES OR GUARANTEES OF ANY KIND. THE DEVELOPER DISCLAIMS ALL EXPRESS, IMPLIED, AND STATUTORY WARRANTIES, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, NON-INFRINGEMENT, ACCURACY, RELIABILITY, SAFETY, COMPATIBILITY, AND UNINTERRUPTED OR ERROR-FREE OPERATION. No statement or feature in Swiftea creates a warranty. Any mandatory warranty or guarantee that applicable law does not allow to be excluded remains in effect."
            ),
            SwifteaLegalSection(
                "12. Assumption of risk and release",
                body: "You knowingly and voluntarily accept the ordinary risks of using software to control heated consumer hardware, including burns, spills, electrical injury, illness, permanent disability, serious bodily injury, death, fire, property damage, data loss, and damage to the mug, charger, Mac, or nearby objects. To the fullest extent permitted by law, you release the Developer from claims for property damage, bodily injury, or death arising from those inherent risks or from the Developer’s ordinary negligence in providing Swiftea. This includes claims arising from or related to software bugs, incorrect or unintended commands, communication failures, inaccurate readings, automation failures, or use of or inability to use Swiftea. This release does not apply to fraud, gross negligence or gross fault, recklessness, willful or intentional misconduct, violation of law, or any responsibility that cannot legally be waived."
            ),
            SwifteaLegalSection(
                "13. Limitation of liability",
                body: "TO THE FULLEST EXTENT PERMITTED BY LAW, THE DEVELOPER WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES; LOSS OF USE, DATA, PROFITS, OR OPPORTUNITY; OR DAMAGE CAUSED BY STALE READINGS, FAILED OR DELAYED COMMANDS, DISCONNECTIONS, AUTOMATION, NOTIFICATIONS, THIRD-PARTY HARDWARE, FIRMWARE, SERVICES, OR MODIFIED BUILDS. If the Developer is found liable despite these terms, total liability for all claims related to Swiftea will not exceed the greater of the amount you paid specifically for the prebuilt Swiftea app distributed by the Developer or US $10. These exclusions and this cap apply regardless of the legal theory asserted, including contract, tort (including ordinary negligence), strict liability, or statute, but only where applicable law permits. They apply to claims involving property damage, bodily injury, or death only where applicable law permits. This section does not apply to the Developer’s fraud, gross negligence or gross fault, recklessness, willful or intentional misconduct, violation of law, or any right or liability that cannot legally be excluded or limited, including under applicable consumer-protection or personal-injury law."
            ),
            SwifteaLegalSection(
                "14. Third-party products and software",
                body: "Swiftea depends on products and services outside the Developer’s control, including Ember hardware and firmware, Apple hardware and macOS, Core Bluetooth, GitHub infrastructure, and the Sparkle update framework. Their availability, behavior, terms, warranties, and privacy practices are their own. Swiftea’s acknowledgements identify open-source reference material and included third-party software."
            ),
            SwifteaLegalSection(
                "15. Changes to these terms",
                body: "The Developer may revise these terms when Swiftea, its risks, or applicable law changes. Swiftea will ask you to accept a materially revised version before continuing to use a prebuilt copy distributed by the Developer. Revised terms apply from their stated effective date. If you do not agree to a revised version, you may stop using and delete Swiftea. The version and effective date shown above identify the terms you accepted."
            ),
            SwifteaLegalSection(
                "16. Rights that cannot be waived",
                body: "These terms do not exclude, restrict, or waive any right, remedy, guarantee, warranty, or liability that applicable law does not permit to be excluded, restricted, or waived. If these terms conflict with such law, that law controls only to the extent of the conflict."
            ),
            SwifteaLegalSection(
                "17. Governing law and general terms",
                body: "California law governs these terms, without regard to conflict-of-law rules, to the extent permitted by applicable law. Courts located in California may hear disputes where legally permitted. If part of these terms is unenforceable, the rest remains in effect and the invalid part will be limited only as much as necessary. A failure to enforce one part is not a waiver. These terms, the Safety Notice, and the 0BSD license form the complete written understanding about prebuilt copies of Swiftea distributed by the Developer, while the 0BSD license remains controlling for source-code permissions."
            ),
            SwifteaLegalSection(
                "18. Contact",
                body: "The Developer is Tomás Papi. Questions about Swiftea can be raised through the public project at https://github.com/tomaspapi/swiftea. Do not post private device information, serial numbers, or other sensitive details in a public issue."
            )
        ]
    )

    static let safetyNotice = SwifteaLegalDocument(
        title: "Safety Notice",
        summary: "Swiftea controls a consumer product that heats liquids. Software convenience does not replace direct supervision and ordinary care.",
        metadata: "Version \(currentSafetyNoticeVersion) · Effective \(effectiveDate)",
        sections: [
            SwifteaLegalSection(
                "Supervise the mug",
                body: "Do not use Swiftea or a heated Ember Mug unattended, while sleeping, near flammable materials, or where children or pets can reach hot liquid or charging equipment. Keep the mug stable and use a temperature that is safe for the person drinking from it."
            ),
            SwifteaLegalSection(
                "Do not rely on the app as a safety control",
                body: "Bluetooth, macOS sleep, another controller, firmware, or hardware can interrupt communication. Heating status, temperature, battery, charging, contents detection, notifications, history, automatic shutoff, and automatic reconnection may be delayed, inaccurate, or unavailable. Always verify the physical mug yourself."
            ),
            SwifteaLegalSection(
                "Software can behave unexpectedly",
                body: "Swiftea is unofficial software and may contain bugs, defects, coding errors, omissions, or unintended behavior. It may send a delayed, repeated, incorrect, or unintended command; fail to send or stop a command; misread or misreport the mug’s state; or interact unexpectedly with the mug’s hardware or firmware. These events can occur even when you use Swiftea correctly and follow every instruction."
            ),
            SwifteaLegalSection(
                "Respond to unexpected behavior",
                body: "If Swiftea and the mug disagree, or if the mug is damaged, leaking, unusually hot, smoking, producing an unusual smell, or behaving unpredictably, stop using it. Turn it off if safe, remove it from the charging coaster, move away from flammable materials, and follow Ember’s official support and safety guidance."
            ),
            SwifteaLegalSection(
                "Use and care for the hardware correctly",
                body: "Never microwave an Ember Mug. Hand wash it as directed by Ember, dry it completely before charging, and use compatible official charging equipment. Follow Ember’s current manuals, warnings, care instructions, and recalls. Swiftea does not change or replace those instructions."
            ),
            SwifteaLegalSection(
                "Avoid competing controllers",
                body: "Close other apps that may be connected to the mug. Competing controllers can cause disconnections, stale information, or commands that do not behave as expected."
            ),
            SwifteaLegalSection(
                "Your acknowledgment",
                body: "By using Swiftea, you acknowledge and voluntarily accept that software bugs, defects, errors, omissions, unintended commands or effects, unreliable connections, unexpected hardware or firmware behavior, ordinary use, misuse, lack of supervision, and other expected or unexpected conditions can cause burns, spills, electrical hazards, fire, property damage, hardware damage, permanent disability, serious bodily injury, or death. These outcomes can occur even when you use Swiftea correctly and follow every instruction. You are responsible for deciding whether to use Swiftea, directly supervising the mug, operating it safely, and stopping use if anything appears unsafe or unexpected. This acknowledgment applies to the fullest extent permitted by law."
            )
        ]
    )
}
