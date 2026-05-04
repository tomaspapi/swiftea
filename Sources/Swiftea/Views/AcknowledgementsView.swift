import AppKit
import SwiftUI

struct AcknowledgementsView: View {
    @State private var contentHeight: CGFloat = 0
    @State private var requiresScrolling = false

    var body: some View {
        Group {
            if requiresScrolling {
                ScrollView {
                    content
                }
            } else {
                content
            }
        }
        .onPreferenceChange(AcknowledgementsContentHeightKey.self) { height in
            contentHeight = ceil(height)
        }
        .background {
            Color(nsColor: .windowBackgroundColor)
            AcknowledgementsWindowFitter(
                contentHeight: contentHeight,
                requiresScrolling: $requiresScrolling
            )
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: !requiresScrolling)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Acknowledgements")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Text("Swiftea is an independent app for controlling an Ember Mug over Bluetooth. It is not affiliated with, sponsored by, authorized by, or endorsed by Ember Technologies, Inc.")
                    .textSelection(.enabled)

                Text("Ember, Ember Mug, Ember Mug 2, and related names and marks are trademarks or property of their respective owners.")
                    .textSelection(.enabled)

                Text("Swiftea’s Bluetooth implementation was informed by public reverse-engineering notes and prior open-source Ember mug projects, including:")
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                AcknowledgementLink(
                    title: "orlopau/ember-mug",
                    detail: "Paul Orlob",
                    url: "https://github.com/orlopau/ember-mug"
                )

                AcknowledgementLink(
                    title: "sopelj/python-ember-mug",
                    detail: "Jesse Sopel",
                    url: "https://github.com/sopelj/python-ember-mug"
                )

                AcknowledgementLink(
                    title: "sopelj/hass-ember-mug-component",
                    detail: "Jesse Sopel and contributors",
                    url: "https://github.com/sopelj/hass-ember-mug-component"
                )

                AcknowledgementLink(
                    title: "importRyan/Muggle",
                    detail: "Ryan Ferrell",
                    url: "https://github.com/importRyan/Muggle"
                )
            }

            Text("These projects were used as public reference material; they are not included inside Swiftea.")
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 12) {
                Text("Included open-source software:")
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)

                AcknowledgementLink(
                    title: "sparkle-project/Sparkle",
                    detail: "Sparkle Project contributors",
                    url: "https://github.com/sparkle-project/Sparkle"
                )

                Text("Sparkle is included in Swiftea to support direct-download app updates. Its license notice is bundled with the app.")
                    .textSelection(.enabled)
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AcknowledgementsContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

private struct AcknowledgementsWindowFitter: NSViewRepresentable {
    let contentHeight: CGFloat
    @Binding var requiresScrolling: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        fitWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        fitWindow(from: nsView)
    }

    private func fitWindow(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard view.window != nil else { return }
                    fitWindow(from: view)
                }
                return
            }

            window.backgroundColor = .windowBackgroundColor
            window.contentView?.layoutSubtreeIfNeeded()
            let fittingSize = window.contentView?.fittingSize ?? .zero
            let naturalContentHeight = contentHeight > 0 ? contentHeight : fittingSize.height
            guard naturalContentHeight > 0 else { return }

            let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 720)
            let maximumContentHeight = max(320, screenFrame.height - 96)
            let shouldScroll = naturalContentHeight > maximumContentHeight
            if requiresScrolling != shouldScroll {
                requiresScrolling = shouldScroll
            }

            let targetContentHeight = min(ceil(naturalContentHeight), maximumContentHeight)
            let currentContentSize = window.contentRect(forFrameRect: window.frame).size
            guard abs(currentContentSize.height - targetContentHeight) > 1 else { return }

            let targetContentSize = NSSize(width: currentContentSize.width, height: targetContentHeight)
            let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
            var targetFrame = window.frame
            targetFrame.origin.y = min(window.frame.maxY - targetFrameSize.height, screenFrame.maxY - targetFrameSize.height)
            targetFrame.origin.y = max(targetFrame.origin.y, screenFrame.minY)
            targetFrame.size = targetFrameSize

            window.setFrame(targetFrame, display: true)
        }
    }
}

private struct AcknowledgementsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AcknowledgementLink: View {
    let title: String
    let detail: String
    let url: String
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("-")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Link(destination: urlValue) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(title)
                            .font(.body.weight(.medium))

                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color(nsColor: .linkColor))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering, !isHovering {
                        NSCursor.pointingHand.push()
                    } else if !hovering, isHovering {
                        NSCursor.pop()
                    }

                    isHovering = hovering
                }
                .onDisappear {
                    if isHovering {
                        NSCursor.pop()
                        isHovering = false
                    }
                }
                .help(url)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var urlValue: URL {
        URL(string: url)!
    }
}

#Preview {
    AcknowledgementsView()
}
