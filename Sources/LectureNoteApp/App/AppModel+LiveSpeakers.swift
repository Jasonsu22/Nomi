import Foundation

/// Telling speakers apart while recording. See `LiveSpeakerTracker` and `SpeakerModelKind`.
extension AppModel {
    /// Starts the chosen live speaker model for a recording run, if it is on and downloaded.
    func startLiveSpeakers(_ meetingID: UUID, offset: TimeInterval) {
        stopLiveSpeakers()
        guard SpeakerModelKind.isEnabled, let local = engine as? LocalEngine else { return }
        let kind = SpeakerModelKind.chosen
        guard kind.isDownloaded else { return }
        let run = meetings.first(where: { $0.id == meetingID })?.audioFiles?.count ?? 1
        let tracker = LiveSpeakerTracker(kind: kind, offset: offset, tag: "R\(run)-") { [weak self] spans, prints in
            Task { @MainActor in
                guard let self, self.speakerTracker != nil else { return }
                self.liveSpeakerSpans = spans
                self.liveSpeakerPrints = prints
            }
        }
        speakerTracker = tracker
        liveSpeakerSpans = []
        liveSpeakerPrints = [:]
        local.onSpeakerAudio = { [tracker] samples in tracker.append(samples) }
        tracker.start()
    }

    private func stopLiveSpeakers() {
        (engine as? LocalEngine)?.onSpeakerAudio = nil
        speakerTracker = nil
        liveSpeakerSpans = []
        liveSpeakerPrints = [:]
    }

    /// The voices of the meeting being recorded, for its live transcript: what earlier runs found,
    /// plus who has spoken in this one.
    func liveVoices(for meeting: Meeting) -> (voices: MeetingVoices, spans: [VoiceSpan])? {
        guard meeting.isLive, !liveSpeakerSpans.isEmpty else { return nil }
        guard var merged = VoiceLabels.merging(meeting.voices, spans: liveSpeakerSpans, prints: liveSpeakerPrints) else { return nil }
        if merged.voices.me == nil, merged.voices.meChosen != true, let mine = MyVoice.print, let prints = merged.voices.prints {
            merged.voices.me = MyVoice.match(mine, in: prints, teacher: merged.voices.teacher)
        }
        return merged
    }

    /// When the recording stops: the live labels are kept with the meeting.
    func finishLiveSpeakers(_ meetingID: UUID) {
        guard let tracker = speakerTracker else { return }
        (engine as? LocalEngine)?.onSpeakerAudio = nil
        tracker.finish { [weak self] spans, prints in
            Task { @MainActor in
                guard let self else { return }
                self.speakerTracker = nil
                self.liveSpeakerSpans = []
                self.liveSpeakerPrints = [:]
                guard let index = self.meetings.firstIndex(where: { $0.id == meetingID }), !self.meetings[index].isLive,
                      var merged = VoiceLabels.merging(self.meetings[index].voices, spans: spans, prints: prints) else { return }
                if merged.voices.me == nil, merged.voices.meChosen != true, let mine = MyVoice.print, let all = merged.voices.prints {
                    merged.voices.me = MyVoice.match(mine, in: all, teacher: merged.voices.teacher)
                }
                self.meetings[index].paragraphs = VoiceLabels.apply(merged.spans, to: self.meetings[index].paragraphs)
                self.meetings[index].voices = merged.voices
            }
        }
    }
}
