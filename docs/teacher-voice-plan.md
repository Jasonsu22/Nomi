# Teacher voice: plan

> Written 2026-11-20. Nothing is built yet. Prompted by voxturn's ShadowMe, which learns one person's voice and
> follows only them. Section 6 has the test on a real lecture; section 8 lists your decisions.

## 1. The problem

A classroom recording holds more than the teacher. In the English class of Nov 8 alone:

- 14:20 "I usually get nervous in front of so many people. I cannot speak…" and 16:07 "I feel uh nervous in the
  presentation" are students answering the teacher.
- Later, students give their own presentations ("the topic of my presentation today is…").
- 15:51 is one 15-second piece in which the teacher asks "Did you present in English before?" and a student answers:
  one recognizer chunk, two voices.

Nomi treats every line as the lecture. So summaries, Q&A and citations can present a classmate's remark as what the
teacher said, and side chatter fills the transcript with noise.

## 2. What voxturn and ShadowMe offer, and why we don't take them as they are

**voxturn** decides when a speaker has finished a turn, for voice agents that reply. Nomi never replies to speech, so
its main job isn't ours. **ShadowMe** adds the part we want: from about 10 s of one person's voice it marks, moment by
moment, whether that person or someone else is speaking.

We can't ship either model:

- **License:** CC BY-NC 4.0, non-commercial only.
- **Platform:** PyTorch on Nvidia GPUs (2.1 B parameters, 4.8 GB of GPU memory). Nomi runs on Apple silicon with MLX
  and Core ML.
- **Languages:** ShadowMe is an English-only preview, and Nomi's classes are often Chinese or mixed.

What we take is the idea: **learn the teacher's voice, then label every stretch of speech as teacher or someone
else.** The author's other repositories are research benchmarks (VoxMem, EnvMem: whether audio models remember *who*
said something) and models for spoofing detection, keyword spotting and sound events. They hold nothing to reuse,
but VoxMem's point supports this plan: who said something matters as much as what was said.

## 3. The tool: FluidAudio

[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0, Swift, v0.18.4) runs speaker models through
Core ML on the Neural Engine, and many Mac transcription apps use it. It gives us:

- a **voice fingerprint** (speaker embedding) for any stretch of audio: WeSpeaker ResNet-34, or CAM++ from
  3D-Speaker, which was trained on Chinese and English and is likely better for our classes;
- **offline diarization** ("who spoke when") over a whole file, with clustering;
- **speaker enrollment**: known voices are given names, and new audio is matched to them.

It's a Swift package, so it can go straight into the app with no Python or GPU. The models download once, as our
Qwen models do. Licenses to confirm before shipping: the WeSpeaker weights are CC BY 4.0 (attribution) and CAM++ is
Apache-2.0.

## 4. Design

**Finding the teacher.** The teacher is almost always the voice that speaks most. After a recording, Nomi groups the
speech by voice and takes the largest group as the teacher; nothing has to be set up. If it guesses wrong, you choose
"This is the teacher" on any transcript line. The teacher's fingerprint is saved per class (category), so the next
lecture of that class recognises the teacher from the first minute.

**Labelling lines.** Each stretch of speech becomes *teacher*, *someone else* or *unsure*. Because one recognizer chunk
can hold two voices (15:51 above), labels are worked out inside the chunk, then laid onto the transcript at sentence
level, using the same time estimate as citations.

**What you see.**
- In the transcript, lines by someone else are greyed with a small "Classmate" tag.
- A "Teacher only" filter hides them.
- Nothing is ever deleted.

**What the AI sees.**
- Passages mark lines as `[student]`, so a summary says "a student said they get nervous" rather than presenting it as
  the teacher's point.
- Q&A and citations prefer the teacher's words.
- "Questions students asked" become easy to find (they feed MeetingQA).

**Where it runs.**
1. First, **after recording**, on the saved audio. That's simplest, works on every lecture you already have, and adds
   nothing to live recording.
2. Later, **live**: a fingerprint per voice-detected segment, sent alongside the recognizer, so lines are labelled as
   they appear.

## 5. Risks

- **Distance:** a student next to the Mac can sound louder and clearer than a teacher at the front. A fingerprint
  measures *who*, not *how loud*, but far-field audio is weaker evidence. Test this first.
- **Classroom Mic:** Apple's voice processing changes how voices sound. Enrol and compare with the same mic setting.
- **Short replies** ("Yes", "Maybe a little bit") under about 1 s are unreliable; mark them *unsure* rather than guess.
- **Two teachers**, or a guest speaker: allow more than one "teacher" voice per class.
- **Overlap:** two people at once. Diarization models handle some overlap; the line stays *unsure*.

## 6. Test results (run 2026-11-20)

I ran FluidAudio v0.18.4's offline diarization on the first 20 minutes of the English class of Nov 8, recorded with
the Mac's own mic from the classroom.

**Speed:** 20 minutes took 12 s on this Mac, about 100× faster than real time.

**Telling voices apart works.** With no setup, it found two voices: one speaking 757 s, the teacher, and one
speaking 50 s, the students together. The second voice landed on the student answers:

| Time | Line | Second voice |
|---|---|---|
| 13:40 | "Ah, final year." | 80% |
| 14:19 | "I usually get nervous in front of so many people. I cannot speak…" | 74% |
| 16:59 | "Oh, I, I, I don't think I have some tips." | 81% |
| 19:54 | "Maybe, uh." | 59% |

Teacher explanations showed 0–9% second voice, which is only noise at the edges.

**Marking single sentences is the weak spot.** Many of Nomi's recognizer chunks run 10–28 s and hold both voices. I
gave each sentence a time from where its words fall in the chunk (the same estimate citations use) and marked it
"someone else" when most of it was the second voice. Of the 22 sentences marked:

- **About 12 are right:** "I usually get nervous…", "I feel nervous, but I can still talk", "I feel uh nervous in the
  presentation", "Maybe, uh."
- **About 10 are the teacher's replies right next to a student:** "How about before that?", "You know your work,
  right?", "Okay, Vincent."

The estimate drifts by a second or two inside long chunks, and that is enough to blur a quick exchange.

**What that means for the design.**
- **For live recording:** split recognizer chunks wherever the voice changes, before transcription. Each line is
  then one voice, and its label is exact. This replaces the time estimate.
- **For recordings already made:** either re-transcribe each voice's stretch, or get word-level times from a forced
  aligner (Qwen3 has one) and label words rather than sentences.
- **Labelling whole lines:** with a high bar (≥ 70% second voice), the 4 lines above are caught and no teacher line
  is wrongly marked. That is safe to ship first.

**Still to measure:** recall, meaning how many student lines it misses. That needs about 10 minutes of lines marked
by you. One case to check by ear: at 11:48, "Oh, I don't like the way how I stand. I don't like my own voice…" was
labelled teacher; it may be the teacher reading out students' answers.

## 7. Work, in order

1. **Test** (section 6). Done; recall still needs 10 minutes of your labelling.
2. **After-recording labelling:** FluidAudio in the app, finding the teacher, `speaker` on transcript sentences
   (optional, so old meetings still load), "This is the teacher". Whole lines only, at the ≥ 70% bar. About 1 day.
3. **Transcript view:** the greyed classmate lines and the "Teacher only" filter. Half a day.
4. **AI:** `[student]` in passages, teacher preferred in Q&A and citations, the questions-students-asked list. Half a
   day.
5. **Live labelling** during recording, with chunks split where the voice changes, so mixed lines get exact labels.
   About 1–2 days.

## 8. Decisions for you

1. **Finding the teacher:** automatic (largest voice), with "This is the teacher" to correct it? **Suggestion: yes.**
2. **Classmates' lines:** greyed with a tag, hidden only by a filter? **Suggestion: greyed, never hidden by default.**
3. **Remember the teacher per class?** **Suggestion: yes,** saved as a voice fingerprint only (no audio), on this Mac.
4. **First version:** after recording only, with live labelling later? **Suggestion: yes.**

## 9. Live speakers: test results (2026-11-20)

The after-recording pass is not enough on its own, so speakers are now labelled while recording. Each
candidate was replayed through Nomi's own live tracker in 0.1 s pieces, as the microphone delivers audio,
on 20 minutes of the English class and 20 minutes of the NLP lecture. Each was compared second by
second with the after-recording pass, which is the reference here, not hand-checked truth.

| Model | Download | English: agree / others caught / teacher marked other | NLP: agree / caught / marked other | Speed |
|---|---|---|---|---|
| Standard (pyannote + WeSpeaker, 5 s chunks, match 0.5) | 36 MB | 92% / 79% / 7.3% | 100% / 100% / 0.2% | 110× real time |
| Sortformer | 236 MB | 93% / 68% / 5.3% | 100% / 99% / 0.3% | 13× |
| Nemotron 3 (low latency) | 195 MB | 92% / 80% / 7.7% | 98% / 99% / 2.4% | 6–12× |
| LS-EEND (all four versions) | 172 MB | merged the students into the teacher | | |
| Streaming diarizer, default match | | merged everyone into one voice | | |

**Results:**
- **Model choice:** Standard, Sortformer and Nemotron 3 are offered in Settings, each downloaded only when
  chosen. Standard is the default: the fastest, the smallest, and it keeps voiceprints for "This Is Me".
- **Label delay:** Standard labels lines about 5 s after they are spoken. Longer 10 s chunks were more
  accurate (96%) but slower to appear; shorter 3 s chunks were less accurate (88%).
