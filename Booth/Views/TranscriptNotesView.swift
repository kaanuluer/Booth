import SwiftUI

struct TranscriptNotesView: View {
    @Binding var episode: Episode
    var mediaRoot: URL
    @EnvironmentObject private var store: EpisodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("On-device konuşma tanıma transkript ve yayın notu üretir. Filler kesimi zaman damgalı kelimeleri oyur.")
                    .font(.system(size: 13))
                    .foregroundStyle(BoothTheme.secondary)
                HStack {
                    Button(isWorking ? "Çözümleniyor…" : "Tüm konuşmayı yaz") {
                        Task { await transcribeAll() }
                    }
                    .buttonStyle(BoothButtonStyle())
                    .disabled(isWorking)
                    Button("Notu yenile") {
                        episode.showNotes = SpeechTranscriber.showNotes(
                            title: episode.title,
                            transcript: episode.transcript,
                            chapters: episode.markers
                        )
                        store.save(episode)
                    }
                    .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                }
                Text("Transkript")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BoothTheme.secondary)
                TextEditor(text: $episode.transcript)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(BoothTheme.text)
                    .padding(8)
                    .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(minHeight: 140)
                Text("Show notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BoothTheme.secondary)
                TextEditor(text: $episode.showNotes)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(BoothTheme.text)
                    .padding(8)
                    .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(minHeight: 140)
                Spacer()
            }
            .padding(24)
            .background(BoothTheme.canvas)
            .navigationTitle("Transkript / notlar")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        store.save(episode, persistImmediately: true)
                        dismiss()
                    }
                }
            }
            .alert("Transkript", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func transcribeAll() async {
        isWorking = true
        defer { isWorking = false }
        let clips = episode.tracks.filter { $0.kind == .voice }.flatMap(\.clips)
        store.checkpoint(episode)
        for clip in clips {
            let url = mediaRoot.appendingPathComponent(clip.playbackFilename)
            do {
                let result = try await SpeechTranscriber.transcribe(url: url)
                episode.applyTranscript(clipID: clip.id, text: result.text, segments: result.segments)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        episode.showNotes = SpeechTranscriber.showNotes(
            title: episode.title,
            transcript: episode.transcript,
            chapters: episode.markers
        )
        store.save(episode, persistImmediately: true)
    }
}
