import AppKit
import SwiftUI

struct LicenseView: View {
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
        .onPreferenceChange(LicenseContentHeightKey.self) { height in
            contentHeight = ceil(height)
        }
        .background {
            Color(nsColor: .windowBackgroundColor)
            LicenseWindowFitter(
                contentHeight: contentHeight,
                requiresScrolling: $requiresScrolling
            )
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: !requiresScrolling)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("License")
                .font(.title2.weight(.semibold))

            Text(Self.licenseText)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
        .foregroundStyle(.primary)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LicenseContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private static let licenseText = """
Zero-Clause BSD

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
"""
}

private struct LicenseWindowFitter: NSViewRepresentable {
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

private struct LicenseContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    LicenseView()
}
