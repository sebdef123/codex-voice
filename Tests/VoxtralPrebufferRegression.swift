import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Voxtral prebuffer regression failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct VoxtralPrebufferRegression {
    static func main() {
        require(VoxtralPrebuffer.options.first == 0.7, "minimum option should be 0.7 seconds")
        require(VoxtralPrebuffer.options.last == 2.5, "maximum option should be 2.5 seconds")
        require(VoxtralPrebuffer.options.contains(VoxtralPrebuffer.defaultSeconds), "default should be selectable")
        require(VoxtralPrebuffer.clamped(0.2) == 0.7, "values below the range should be clamped")
        require(VoxtralPrebuffer.clamped(3.0) == 2.5, "values above the range should be clamped")
        require(VoxtralPrebuffer.clamped(1.8) == 1.8, "values inside the range should be preserved")
        print("Voxtral prebuffer regression: ok")
    }
}
