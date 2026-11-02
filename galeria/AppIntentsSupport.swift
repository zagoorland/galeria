import AppIntents

/// A minimal Shortcuts entry point. Keeping Galeria's App Intents metadata
/// meaningful also keeps the Xcode metadata extraction step quiet.
struct OpenGaleriaIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Galeria"
    static var description = IntentDescription("Bring Galeria to the front to browse a folder of images.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
