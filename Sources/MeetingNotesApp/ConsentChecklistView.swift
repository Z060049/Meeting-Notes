import AppKit
import MeetingNotesCore
import SwiftUI

struct ConsentChecklistView: View {
    @ObservedObject var controller: MeetingNotesController
    @State private var understandsConsent = false
    @State private var understandsIndicator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before recording")
                .font(.headline)

            Text("Recording laws vary by location. Only record conversations when you have the required consent.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("I understand I am responsible for consent.", isOn: $understandsConsent)
            Toggle("I understand MeetingNotes shows recording state while active.", isOn: $understandsIndicator)

            Button("Accept and Continue") {
                controller.acceptConsentChecklist()
            }
            .disabled(!understandsConsent || !understandsIndicator)
        }
    }
}
