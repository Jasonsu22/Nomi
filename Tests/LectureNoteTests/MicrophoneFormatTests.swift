import AVFoundation
import Foundation
import NomiObjCSupport
import Testing
@testable import LectureNoteApp

struct MicrophoneFormatTests {
    @Test func aBluetoothHeadsetUsesTheRateItSwitchedTo() throws {
        // AirPods report 48 kHz until their microphone opens, then run at 24 kHz.
        let stale = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let format = microphoneTapFormat(reported: stale, hardwareRate: 24_000)
        #expect(format.sampleRate == 24_000)
        #expect(format.channelCount == 1)
    }

    @Test func aMatchingOrUnknownRateKeepsTheReportedFormat() throws {
        let reported = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        #expect(microphoneTapFormat(reported: reported, hardwareRate: 48_000) === reported)
        #expect(microphoneTapFormat(reported: reported, hardwareRate: nil) === reported)
        #expect(microphoneTapFormat(reported: reported, hardwareRate: 0) === reported)
    }

    @Test func anObjectiveCExceptionBecomesAReason() {
        var reason: NSString?
        let succeeded = NomiCatchException({
            NSException(name: .invalidArgumentException, reason: "Format mismatch", userInfo: nil).raise()
        }, &reason)
        #expect(!succeeded)
        #expect((reason as String?)?.contains("Format mismatch") == true)

        var untouched: NSString?
        #expect(NomiCatchException({}, &untouched))
        #expect(untouched == nil)
    }
}
