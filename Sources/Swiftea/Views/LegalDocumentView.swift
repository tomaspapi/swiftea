import AppKit
import SwiftUI

struct LegalDocumentView: View {
    let document: SwifteaLegalDocument
    @State private var contentHeight: CGFloat = 0
    @State private var requiresScrolling = true

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
        .onPreferenceChange(LegalDocumentContentHeightKey.self) { height in
            contentHeight = ceil(height)
        }
        .background {
            Color(nsColor: .windowBackgroundColor)
            LegalDocumentWindowFitter(
                contentHeight: contentHeight,
                requiresScrolling: $requiresScrolling
            )
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: !requiresScrolling)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(document.title)
                    .font(.title2.weight(.semibold))

                Text(document.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text(document.metadata)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            ForEach(document.sections) { section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title)
                        .font(.headline)

                    Text(section.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                }
            }
        }
        .textSelection(.enabled)
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LegalDocumentContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

private struct LegalDocumentWindowFitter: NSViewRepresentable {
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
            let naturalContentHeight = contentHeight
            guard naturalContentHeight > 0 else { return }

            let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1024, height: 720)
            let maximumContentHeight = max(360, screenFrame.height - 96)
            let shouldScroll = naturalContentHeight > maximumContentHeight
            if requiresScrolling != shouldScroll {
                requiresScrolling = shouldScroll
            }

            let targetContentHeight = min(naturalContentHeight, maximumContentHeight)
            let currentContentSize = window.contentRect(forFrameRect: window.frame).size
            guard abs(currentContentSize.height - targetContentHeight) > 1 else { return }

            let targetContentSize = NSSize(width: currentContentSize.width, height: targetContentHeight)
            let targetFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetContentSize)
            ).size
            var targetFrame = window.frame
            targetFrame.origin.y = min(
                window.frame.maxY - targetFrameSize.height,
                screenFrame.maxY - targetFrameSize.height
            )
            targetFrame.origin.y = max(targetFrame.origin.y, screenFrame.minY)
            targetFrame.size = targetFrameSize
            window.setFrame(targetFrame, display: true)
        }
    }
}

private struct LegalDocumentContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Terms") {
    LegalDocumentView(document: SwifteaLegalDocuments.termsOfUse)
}

#Preview("Safety") {
    LegalDocumentView(document: SwifteaLegalDocuments.safetyNotice)
}
