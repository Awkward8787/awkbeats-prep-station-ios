import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("producerName") private var producerName = ""
    @AppStorage("producerPromptDone") private var producerPromptDone = false
    @State private var showProducerPrompt = false
    @State private var importError: String?

    var body: some View {
        LibraryView()
            .onOpenURL { url in
                Task { await importShared(url) }
            }
            .onAppear {
                if !LaunchFlags.demo && !producerPromptDone && producerName.isEmpty { showProducerPrompt = true }
            }
            .sheet(isPresented: $showProducerPrompt) {
                ProducerPromptSheet { name in
                    producerName = name
                    producerPromptDone = true
                }
                .presentationDetents([.medium])
                .interactiveDismissDisabled(false)
                .onDisappear { producerPromptDone = true }
            }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
    }

    private func importShared(_ url: URL) async {
        do { try await BeatImporter.importFile(url, into: context, defaultProducer: producerName) }
        catch { importError = error.localizedDescription }
    }
}

struct ProducerPromptSheet: View {
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image("AwkBeatsLogo").resizable().scaledToFit().frame(height: 36).accessibilityHidden(true)
            Text("What name do you produce under?")
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Text("Prep Station fills it in as the producer on every beat you import. You can change it later in Settings.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
            TextField("Producer name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(12)
                .background(Theme.plum850, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.lineControl))
                .submitLabel(.done)
                .onSubmit(save)
            Button("Save", action: save).buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Not now") { dismiss() }
                .font(.subheadline).foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.plum900)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
