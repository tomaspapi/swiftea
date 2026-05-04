import AppKit
import SwiftUI

struct MugSidebarRow: View {
    let mug: AppModel.SidebarMugItem
    @Binding var nameDraft: String
    let isEditingName: Bool
    let commitRename: () -> Void
    let cancelRename: () -> Void

    init(
        mug: AppModel.SidebarMugItem,
        nameDraft: Binding<String> = .constant(""),
        isEditingName: Bool = false,
        commitRename: @escaping () -> Void = {},
        cancelRename: @escaping () -> Void = {}
    ) {
        self.mug = mug
        _nameDraft = nameDraft
        self.isEditingName = isEditingName
        self.commitRename = commitRename
        self.cancelRename = cancelRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditingName {
                SidebarRenameTextField(
                    text: $nameDraft,
                    commit: commitRename,
                    cancel: cancelRename
                )
                .frame(height: 19)
            } else {
                Text(mug.name)
                    .foregroundStyle(titleForegroundStyle)
                    .lineLimit(1)
            }

            Text(mug.subtitle)
                .font(.caption)
                .foregroundStyle(subtitleForegroundStyle)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private var isMuted: Bool {
        !mug.isConnected
    }

    private var titleForegroundStyle: HierarchicalShapeStyle {
        isMuted ? .secondary : .primary
    }

    private var subtitleForegroundStyle: HierarchicalShapeStyle {
        isMuted ? .tertiary : .secondary
    }
}

private struct SidebarRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let commit: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.font = .preferredFont(forTextStyle: .body)
        textField.delegate = context.coordinator
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard !context.coordinator.didFocus else { return }
        context.coordinator.didFocus = true
        DispatchQueue.main.async {
            guard let window = textField.window else { return }
            window.makeFirstResponder(textField)
            textField.currentEditor()?.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SidebarRenameTextField
        var didFocus = false
        private var didCancel = false

        init(parent: SidebarRenameTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !didCancel else { return }
            parent.commit()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.commit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                didCancel = true
                parent.cancel()
                return true
            default:
                return false
            }
        }
    }
}

#Preview {
    MugSidebarRow(
        mug: .init(
            identifier: "PREVIEW",
            name: "Desk Mug",
            subtitle: "Connected now",
            signalLabel: nil,
            finish: .black,
            size: .ounce10,
            kind: .current,
            isConnected: true,
            isPreferred: true
        )
    )
    .padding()
}
