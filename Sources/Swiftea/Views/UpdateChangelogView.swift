import AppKit
import SwiftUI

struct UpdateChangelogView: View {
    @State private var contentHeight: CGFloat = 0
    @State private var requiresScrolling = false

    private let version: String
    private let releaseNotes: [String]

    init(
        version: String = AppVersion.currentMarketingVersion(),
        markdown: String = PublishedChangelog.currentReleaseNotesMarkdown()
    ) {
        self.version = version
        releaseNotes = PublishedChangelog.releaseNoteItems(from: markdown)
    }

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
        .onPreferenceChange(UpdateChangelogContentHeightKey.self) { height in
            contentHeight = ceil(height)
        }
        .background {
            Color(nsColor: .windowBackgroundColor)
            UpdateChangelogWindowFitter(
                contentHeight: contentHeight,
                requiresScrolling: $requiresScrolling
            )
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: !requiresScrolling)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What’s New")
                    .font(.title2.weight(.semibold))

                Text("Swiftea \(version)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(releaseNotes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .accessibilityHidden(true)
                        Text(note)
                            .lineSpacing(4)
                    }
                }
            }
            .textSelection(.enabled)
        }
        .font(.body)
        .foregroundStyle(.primary)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: UpdateChangelogContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

private struct UpdateChangelogWindowFitter: NSViewRepresentable {
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
            let maximumContentHeight = max(300, screenFrame.height - 96)
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

private struct UpdateChangelogContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    UpdateChangelogView()
}
