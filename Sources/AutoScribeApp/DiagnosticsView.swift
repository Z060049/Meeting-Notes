import AppKit
import AutoScribeCore
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var controller: AutoScribeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Copy Validation Report") {
                    copyValidationReport()
                }
                Button("Copy") {
                    copyDiagnostics()
                }
                Button("Clear") {
                    controller.clearDiagnostics()
                }
            }

            if controller.diagnostics.isEmpty {
                Text("No diagnostic events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(controller.diagnostics) { event in
                            Text(event.formatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: event.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 160)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func copyDiagnostics() {
        let text = controller.diagnostics.map(\.formatted).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyValidationReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.validationReportText(), forType: .string)
    }

    private func color(for level: DiagnosticEvent.Level) -> Color {
        switch level {
        case .info:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
