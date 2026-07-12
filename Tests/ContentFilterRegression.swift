import Foundation

@main
struct ContentFilterRegression {
    static func main() {
        expect(
            ContentFilter.prepareForSpeech("## Titre\nVoici **une** [reponse](https://example.com).\n\n```swift\nprint(\"bonjour\")\n```") ,
            equals: "Titre\nVoici une reponse.\n\nBloc de code ignoré.",
            name: "markdown and code filtering"
        )
        expect(
            ContentFilter.prepareForCommentary("Voici **une** phrase de demarrage."),
            equals: "Voici une phrase de demarrage.",
            name: "commentary markdown filtering"
        )
        expectNil(
            ContentFilter.prepareForCommentary("exec_command returned stdout with session id 42"),
            name: "tool commentary suppression"
        )
        expect(
            ContentFilter.prepareForSpeech("La mise a jour est prete.\nSkill utilisée : browser"),
            equals: "La mise a jour est prete.",
            name: "French skill marker suppression"
        )
        expectNil(
            ContentFilter.prepareForCommentary("Skill used: browser"),
            name: "English skill marker suppression"
        )
        expect(
            PronunciationDictionary.applyForMacOSVoice(to: "GitHub et macOS sont excellents."),
            equals: "Guite-hub et mac-O-S sont excellents.",
            name: "pronunciation dictionary capitalization"
        )
        let longProse = String(repeating: "Cette phrase longue doit rester entiere dans la lecture. ", count: 8)
            .trimmingCharacters(in: .whitespaces)
        expect(
            ContentFilter.prepareForSpeech(longProse),
            equals: longProse,
            name: "long prose is never cut mid-sentence"
        )
        expect(
            String(VoxtralVoiceCatalog.all.count),
            equals: "20",
            name: "complete Voxtral voice catalog"
        )
        expect(
            VoxtralVoiceCatalog.recommended.first?.identifier,
            equals: "fr_female",
            name: "Voxtral default voice"
        )
        expect(
            String(VoxtralVoiceCatalog.recommended.count),
            equals: "2",
            name: "Voxtral recommended voices are concise"
        )
        var commentaryPolicy = CommentaryDeliveryPolicy()
        expect(
            String(describing: commentaryPolicy.decision(at: Date(timeIntervalSince1970: 0))),
            equals: "emit",
            name: "first commentary is spoken"
        )
        expect(
            String(describing: commentaryPolicy.decision(at: Date(timeIntervalSince1970: 5))),
            equals: "cooldown",
            name: "short commentary burst is muted"
        )
        expect(
            String(describing: commentaryPolicy.decision(at: Date(timeIntervalSince1970: 12))),
            equals: "emit",
            name: "later commentary is spoken"
        )
        expect(
            String(describing: commentaryPolicy.decision(at: Date(timeIntervalSince1970: 24))),
            equals: "emit",
            name: "third commentary is spoken"
        )
        expect(
            String(describing: commentaryPolicy.decision(at: Date(timeIntervalSince1970: 36))),
            equals: "limitReached",
            name: "commentary turn limit"
        )
        print("ContentFilterRegression: ok")
    }

    private static func expect(_ actual: String?, equals expected: String, name: String) {
        guard actual == expected else {
            fputs("FAILED \(name): expected=\(expected.debugDescription) actual=\(actual.debugDescription)\n", stderr)
            exit(1)
        }
    }

    private static func expectNil(_ actual: String?, name: String) {
        guard actual == nil else {
            fputs("FAILED \(name): expected nil actual=\(actual.debugDescription)\n", stderr)
            exit(1)
        }
    }
}
