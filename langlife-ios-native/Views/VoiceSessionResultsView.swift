import SwiftUI

struct VoiceSessionResultsView: View {
    let transcript: [VoiceTranscriptEntry]
    let durationSeconds: Int
    let totalTurns: Int
    let newCards: [VoiceSessionCompleteResponse.NewCard]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    summarySection
                    if !newCards.isEmpty {
                        newCardsSection
                    }
                    transcriptSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Nice work!")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 24) {
                StatItem(label: "Duration", value: formattedDuration)
                StatItem(label: "Your turns", value: "\(totalTurns)")
                if !newCards.isEmpty {
                    StatItem(label: "New cards", value: "\(newCards.count)")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var newCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .foregroundStyle(AppColors.accent)
                Text("\(newCards.count) new flashcard\(newCards.count == 1 ? "" : "s") created")
                    .font(.headline)
            }

            Text("Head to the Study tab to review your new vocabulary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(transcript) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.role == .agent ? "AI" : "You")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        Text(entry.text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)

                    if entry.id != transcript.last?.id {
                        Divider()
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

private struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
