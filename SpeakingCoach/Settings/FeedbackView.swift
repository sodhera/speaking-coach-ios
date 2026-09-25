import PhotosUI
import Supabase
import SwiftUI

/// Send feedback: a few words and, if it helps, one screenshot. It lands
/// where the old app's feedback always did — a `feedback` row in `reports`,
/// the screenshot in the `feedback_screenshots` bucket.
struct FeedbackView: View {
    let userID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var sending = false
    @State private var sent = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.1)
            if sent { thanks } else { composer }
        }
        .statusBarScrim()
        .animation(.easeInOut(duration: 0.3), value: sent)
        .onAppear {
            Analytics.enter("feedback")
            focused = true
        }
        .onChange(of: item) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                screenshot = UIImage(data: data)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Send feedback")
                                .font(Typeface.hero(28))
                                .foregroundStyle(Palette.ink)
                            Text("Something broken, confusing, or missing? We read every message.")
                                .font(Typeface.body(15))
                                .foregroundStyle(Palette.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Space.md)
                        GlassIconButton(systemImage: "xmark", size: 40, iconSize: 14, color: Palette.dim, accessibilityLabel: "Close") { dismiss() }
                    }

                    TextField("", text: $text, prompt: Text("Tell us what happened…").foregroundStyle(Palette.muted), axis: .vertical)
                        .lineLimit(5...12)
                        .focused($focused)
                        .modifier(InputChrome(focused: focused))
                        .onChange(of: text) { _, value in
                            if value.count > 4000 { text = String(value.prefix(4000)) }
                        }

                    if let screenshot {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: screenshot)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                            GlassIconButton(systemImage: "xmark", size: 32, iconSize: 12, color: Palette.dim, accessibilityLabel: "Remove screenshot") {
                                self.screenshot = nil
                                item = nil
                            }
                            .padding(Space.sm)
                        }
                    } else {
                        PhotosPicker(selection: $item, matching: .screenshots) {
                            Label("Add a screenshot", systemImage: "photo")
                                .font(Typeface.label(15))
                                .foregroundStyle(Palette.coralDeep)
                                .frame(minHeight: 44)
                        }
                    }

                    if let problem {
                        Text(problem)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.coralDeep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: "Send", systemImage: "paperplane.fill", isLoading: sending) {
                Task { await send() }
            }
            .disabled(trimmed.isEmpty)
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.sm)
        }
    }

    private var thanks: some View {
        StatusScreen(
            title: "Thank you",
            message: "Your feedback is on its way. It genuinely shapes what we build next.",
            primary: StatusScreen.Action(title: "Done") { dismiss() }
        )
    }

    private func send() async {
        focused = false
        sending = true
        problem = nil
        defer { sending = false }
        do {
            try await FeedbackService.submit(text: trimmed, screenshot: screenshot, userID: userID)
            Haptics.success()
            Analytics.action("feedback")
            sent = true
        } catch {
            Haptics.error()
            problem = "Your feedback couldn't be sent. Check your connection and try again."
        }
    }
}

enum FeedbackService {
    static func submit(text: String, screenshot: UIImage?, userID: UUID?) async throws {
        let client = Backend.supabase
        let signedIn = try? await client.auth.session.user.id
        guard let userID = signedIn ?? userID else { throw PracticeAPIError.signedOut }
        var path: String?
        var publicURL: String?
        if let screenshot, let data = jpeg(screenshot) {
            let name = "\(userID.uuidString.lowercased())_\(UUID().uuidString.lowercased()).jpg"
            try await client.storage.from("feedback_screenshots").upload(name, data: data, options: FileOptions(contentType: "image/jpeg"))
            path = name
            publicURL = try? client.storage.from("feedback_screenshots").getPublicURL(path: name).absoluteString
        }
        struct Analysis: Encodable {
            let kind = "feedback"
            let text: String
            let screenshot_path: String?
            let screenshot_url: String?
            let app: String
            let device: String
        }
        struct Row: Encodable {
            let user_id: UUID
            let persona_id = "feedback"
            let scenario_id = "feedback"
            let goal_text: String
            let transcript: [String] = []
            let analysis: Analysis
            let score = 0
        }
        let info = Bundle.main.infoDictionary
        let app = "ios \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let device = await "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
        try await client.from("reports").insert(Row(
            user_id: userID,
            goal_text: text,
            analysis: Analysis(text: text, screenshot_path: path, screenshot_url: publicURL, app: app, device: device)
        )).execute()
    }

    /// Screenshots are shrunk to 1600pt on the long side: plenty to read.
    private static func jpeg(_ image: UIImage) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longSide, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
