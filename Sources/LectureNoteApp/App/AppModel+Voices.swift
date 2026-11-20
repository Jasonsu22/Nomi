import Foundation

/// Telling the teacher's voice from classmates' after a recording. See `MeetingVoices`.
extension AppModel {
    /// Runs the voice pass on a finished meeting and labels its lines. Automatic runs (after a
    /// recording ends) follow the setting and wait while another recording is going.
    func checkVoices(_ id: UUID, automatic: Bool = false) {
        guard !checkingVoices.contains(id),
              let meeting = meetings.first(where: { $0.id == id }), !meeting.isLive,
              let files = meeting.audioFiles, !files.isEmpty else { return }
        if automatic, !ClassmateVoicesPreference.isOn || recordingMeetingID != nil { return }
        checkingVoices.insert(id)
        voiceError[id] = nil
        Task { @MainActor [weak self] in
            defer { self?.checkingVoices.remove(id) }
            do {
                let spans = try await VoiceAnalyzer.shared.spans(meetingID: id, audioFiles: files)
                guard let self, let index = self.meetings.firstIndex(where: { $0.id == id }), !self.meetings[index].isLive else { return }
                guard let labelled = VoiceLabels.label(self.meetings[index].paragraphs, spans: spans) else {
                    self.voiceError[id] = tr("录音里没有找到说话声。")
                    return
                }
                self.meetings[index].paragraphs = labelled.paragraphs
                self.meetings[index].voices = labelled.voices
            } catch is CancellationError {
            } catch {
                self?.voiceError[id] = trf("无法识别声音：%@", error.localizedDescription)
            }
        }
    }

    /// "This is the teacher" on a paragraph: its other voice becomes the teacher's.
    func markTeacher(meetingID: UUID, paragraphID: Int) {
        guard let index = meetings.firstIndex(where: { $0.id == meetingID }),
              var voices = meetings[index].voices,
              let paragraph = meetings[index].paragraphs.first(where: { $0.id == paragraphID }),
              let voice = VoiceLabels.voiceToPromote(in: paragraph, voices: voices) else { return }
        voices.teacher = voice
        meetings[index].voices = voices
    }
}
