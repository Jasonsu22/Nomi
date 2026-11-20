import Foundation

/// Telling the teacher's voice, yours and classmates' apart after a recording. See `MeetingVoices`.
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
                let found = try await VoiceAnalyzer.shared.spans(meetingID: id, audioFiles: files)
                guard let self, let index = self.meetings.firstIndex(where: { $0.id == id }), !self.meetings[index].isLive else { return }
                guard let labelled = VoiceLabels.label(self.meetings[index].paragraphs, spans: found.spans) else {
                    self.voiceError[id] = tr("录音里没有找到说话声。")
                    return
                }
                var voices = labelled.voices
                voices.prints = found.prints
                if let mine = MyVoice.print { voices.me = MyVoice.match(mine, in: found.prints, teacher: voices.teacher) }
                self.meetings[index].paragraphs = labelled.paragraphs
                self.meetings[index].voices = voices
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
        if voices.me == voice { voices.me = nil }
        meetings[index].voices = voices
    }

    /// "This is me" on a paragraph: its main non-teacher voice is yours. Your voice is remembered and
    /// looked for in every other lecture whose voices have been told apart, unless you chose there yourself.
    func markMe(meetingID: UUID, paragraphID: Int) {
        guard let index = meetings.firstIndex(where: { $0.id == meetingID }),
              var voices = meetings[index].voices,
              let paragraph = meetings[index].paragraphs.first(where: { $0.id == paragraphID }),
              let voice = VoiceLabels.mainVoice(in: paragraph, excluding: voices.teacher) else { return }
        voices.me = voice
        voices.meChosen = true
        meetings[index].voices = voices
        guard let print = voices.prints?[voice] else { return }
        let mine = MyVoice.blended(MyVoice.print, with: print)
        MyVoice.print = mine
        findMe(using: mine, skipping: meetingID)
    }

    /// "This isn't me": this recording has none of your voice.
    func clearMe(meetingID: UUID) {
        guard let index = meetings.firstIndex(where: { $0.id == meetingID }), var voices = meetings[index].voices else { return }
        voices.me = nil
        voices.meChosen = true
        meetings[index].voices = voices
    }

    /// Finds your saved voice in the other lectures.
    private func findMe(using mine: [Float], skipping skipped: UUID) {
        var updated = meetings
        var changed = false
        for index in updated.indices where updated[index].id != skipped {
            guard var voices = updated[index].voices, voices.meChosen != true, let prints = voices.prints else { continue }
            let match = MyVoice.match(mine, in: prints, teacher: voices.teacher)
            guard match != voices.me else { continue }
            voices.me = match
            updated[index].voices = voices
            changed = true
        }
        if changed { meetings = updated }
    }
}
