import CoreGraphics
import Foundation
import Testing
@testable import DictateCore

@Suite("Timed words")
struct TimedWordTests {
    @Test func tokensJoinIntoWordsAtSentencePieceBoundaries() {
        let tokens: [(text: String, start: TimeInterval, end: TimeInterval)] = [
            ("▁Hel", 0.0, 0.2), ("lo", 0.2, 0.4), ("<blank>", 0.4, 0.5), ("▁wor", 0.6, 0.8), ("ld", 0.8, 1.0), (".", 1.0, 1.05),
        ]
        let words = TimedWord.words(fromTokens: tokens)
        #expect(words == [TimedWord("Hello", start: 0, end: 0.4), TimedWord("world.", start: 0.6, end: 1.05)])
    }

    @Test func spaceMarksAWordToo() {
        let words = TimedWord.words(fromTokens: [(" Hi", 0, 0.3), (" there", 0.3, 0.7), ("<|endoftext|>", 0.7, 0.7)])
        #expect(words.map(\.text) == ["Hi", "there"])
    }

    @Test func noTokensNoWords() {
        #expect(TimedWord.words(fromTokens: []).isEmpty)
        #expect(TimedWord.words(fromTokens: [("<pad>", 0, 1)]).isEmpty)
    }

    @Test func spreadCoversTheWholeDurationByLength() {
        let words = TimedWord.spread("a bb ccc", over: 6)
        #expect(words.map(\.text) == ["a", "bb", "ccc"])
        #expect(words.first?.start == 0)
        #expect(abs((words.last?.end ?? 0) - 6) < 0.0001)
        #expect(abs(words[1].end - words[1].start - 2) < 0.0001)
    }

    @Test func spreadSplitsTextWithoutSpacesIntoCharacters() {
        let words = TimedWord.spread("今天天气很好我们去公园散步吧然后一起吃午饭好不好呢", over: 10)
        #expect(words.count == 25)
    }

    @Test func spreadOfNothingIsEmpty() {
        #expect(TimedWord.spread("   ", over: 5).isEmpty)
        #expect(TimedWord.spread("hello", over: 0).isEmpty)
    }

    @Test func cleanedDropsAnnotationsAndKeepsTimings() {
        let raw = TimedTranscript(text: "[BLANK_AUDIO] Hello there", words: [
            TimedWord("[BLANK_AUDIO]", start: 0, end: 1), TimedWord("Hello", start: 1, end: 1.4), TimedWord("there", start: 1.5, end: 2),
        ])
        let cleaned = raw.cleaned(duration: 2)
        #expect(cleaned?.text == "Hello there")
        #expect(cleaned?.words.map(\.text) == ["Hello", "there"])
        #expect(cleaned?.words.first?.start == 1)
    }

    @Test func cleanedSpreadsWhenTheEngineHasNoTimings() {
        let cleaned = TimedTranscript(text: "One two three").cleaned(duration: 3)
        #expect(cleaned?.words.count == 3)
        #expect(TimedTranscript(text: "*music*").cleaned(duration: 3) == nil)
    }
}

@Suite("Subtitles")
struct SubtitleTests {
    /// Words of `length` letters, one every `step` seconds.
    private func words(_ count: Int, step: TimeInterval = 0.4, length: Int = 4, from start: TimeInterval = 0) -> [TimedWord] {
        (0..<count).map { index in
            let time = start + Double(index) * step
            return TimedWord(String(repeating: "w", count: length), start: time, end: time + step * 0.8)
        }
    }

    @Test func shortSpeechIsOneCue() {
        let cues = Subtitles.cues(from: [TimedWord("Hello", start: 0.5, end: 0.9), TimedWord("there.", start: 1.0, end: 1.6)])
        #expect(cues == [SubtitleCue(start: 0.5, end: 1.6, lines: ["Hello there."])])
    }

    @Test func aPauseStartsANewCue() {
        let cues = Subtitles.cues(from: [TimedWord("First", start: 0, end: 0.5), TimedWord("second", start: 2, end: 2.5)])
        #expect(cues.count == 2)
        #expect(cues[1].start == 2)
    }

    @Test func cuesStayUnderTwoLinesAndSixSeconds() {
        let cues = Subtitles.cues(from: words(60))
        #expect(cues.count > 1)
        for cue in cues {
            #expect(cue.lines.count <= Subtitles.maxLines)
            #expect(cue.lines.allSatisfy { $0.count <= Subtitles.lineLength })
            #expect(cue.end - cue.start <= Subtitles.maxDuration + 0.0001)
        }
        // Every word lands in exactly one cue, in order.
        let total = cues.flatMap { $0.lines.joined(separator: " ").split(separator: " ") }.count
        #expect(total == 60)
        #expect(zip(cues, cues.dropFirst()).allSatisfy { $0.end <= $1.start })
    }

    @Test func aFinishedSentenceEndsTheCue() {
        let cues = Subtitles.cues(from: [
            TimedWord("This", start: 0, end: 0.4), TimedWord("is", start: 0.5, end: 0.8), TimedWord("done.", start: 0.9, end: 1.6),
            TimedWord("Next", start: 1.7, end: 2.0),
        ])
        #expect(cues.map(\.lines) == [["This is done."], ["Next"]])
    }

    @Test func aVeryShortCueGetsAMomentWithoutOverlapping() {
        let cues = Subtitles.cues(from: [TimedWord("Yes.", start: 0, end: 0.2), TimedWord("No.", start: 1.5, end: 1.7)])
        #expect(cues[0].end == 1)
        #expect(cues[1].end == 2.5)
        let tight = Subtitles.cues(from: [TimedWord("Yes", start: 0, end: 0.2), TimedWord("no", start: 1.0, end: 1.2)])
        #expect(tight[0].end <= tight[1].start)
    }

    @Test func wrapBalancesTwoLines() {
        let lines = Subtitles.wrap("The quick brown fox jumps over the lazy dog and runs away")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.count <= Subtitles.lineLength })
        #expect(abs(lines[0].count - lines[1].count) < 12)
        #expect(Subtitles.wrap("Short line") == ["Short line"])
    }

    @Test func noWordsNoCues() {
        #expect(Subtitles.cues(from: []).isEmpty)
    }
}

@Suite("Transcript formats")
struct TranscriptFormatTests {
    private let transcript = TimedTranscript(text: "Hello there. General Kenobi.", words: [
        TimedWord("Hello", start: 0, end: 0.5), TimedWord("there.", start: 0.6, end: 1.6),
        TimedWord("General", start: 3723.4, end: 3723.9), TimedWord("Kenobi.", start: 3724, end: 3724.5),
    ])

    @Test func plainTextIsTheTranscriptWithAFinalNewline() {
        #expect(TranscriptFormat.plainText.render(transcript) == "Hello there. General Kenobi.\n")
    }

    @Test func subRipNumbersCuesWithCommaMilliseconds() {
        let srt = TranscriptFormat.subRip.render(transcript)
        #expect(srt == """
        1
        00:00:00,000 --> 00:00:01,600
        Hello there.

        2
        01:02:03,400 --> 01:02:04,500
        General Kenobi.

        """)
    }

    @Test func webVTTHasAHeaderAndDotMilliseconds() {
        let vtt = TranscriptFormat.webVTT.render(transcript)
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:01.600\nHello there.\n"))
        #expect(vtt.contains("01:02:03.400 --> 01:02:04.500\nGeneral Kenobi.\n"))
    }

    @Test func timestampsRoundToMilliseconds() {
        #expect(TranscriptFormat.timestamp(59.9996, separator: ",") == "00:01:00,000")
        #expect(TranscriptFormat.timestamp(-1, separator: ".") == "00:00:00.000")
    }

    @Test func extensionsMatchTheFormats() {
        #expect(TranscriptFormat.allCases.map(\.fileExtension) == ["txt", "srt", "vtt"])
    }
}

@Suite("Menu bar icon placement")
struct StatusItemPlacementTests {
    // A 1512×982 notched laptop screen; the notch spans x 662...850.
    private let laptop = StatusItemPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        topLeftArea: CGRect(x: 0, y: 950, width: 662, height: 32),
        topRightArea: CGRect(x: 850, y: 950, width: 662, height: 32))
    private let external = StatusItemPlacement.Screen(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

    @Test func notchComesFromTheAreasEitherSide() {
        #expect(laptop.notch == CGRect(x: 662, y: 950, width: 188, height: 32))
        #expect(external.notch == nil)
    }

    @Test func anIconRightOfTheNotchIsVisible() {
        #expect(!StatusItemPlacement.isHidden(itemFrame: CGRect(x: 1029, y: 958, width: 32, height: 24), isOnScreen: true,
                                              screens: [laptop]))
    }

    @Test func anIconUnderTheNotchIsHidden() {
        #expect(StatusItemPlacement.isHidden(itemFrame: CGRect(x: 740, y: 958, width: 32, height: 24), isOnScreen: true,
                                             screens: [laptop]))
    }

    @Test func offScreenOrOrderedOutIsHidden() {
        let frame = CGRect(x: 1029, y: 958, width: 32, height: 24)
        #expect(StatusItemPlacement.isHidden(itemFrame: frame, isOnScreen: false, screens: [laptop]))
        #expect(StatusItemPlacement.isHidden(itemFrame: CGRect(x: -400, y: 2000, width: 32, height: 24), isOnScreen: true,
                                             screens: [laptop]))
        #expect(StatusItemPlacement.isHidden(itemFrame: nil, isOnScreen: true, screens: [laptop]))
        #expect(StatusItemPlacement.isHidden(itemFrame: CGRect(x: 1029, y: 958, width: 0, height: 0), isOnScreen: true,
                                             screens: [laptop]))
    }

    @Test func theMiddleOfAnExternalScreenIsFine() {
        #expect(!StatusItemPlacement.isHidden(itemFrame: CGRect(x: 2800, y: 1416, width: 32, height: 24), isOnScreen: true,
                                              screens: [laptop, external]))
    }

    @Test func noScreenInfoMeansAssumeVisible() {
        #expect(!StatusItemPlacement.isHidden(itemFrame: CGRect(x: 10, y: 10, width: 32, height: 24), isOnScreen: true, screens: []))
    }
}
