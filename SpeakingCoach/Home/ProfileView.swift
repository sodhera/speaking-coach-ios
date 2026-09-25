import SwiftUI

/// **Profile — you, and what you've done.** Your name as the title, the
/// gear beside it, then your history. The email, the routine
/// and everything else account-shaped live in Settings.
struct ProfileView: View {
    let model: AppModel
    var onOpenReport: (PracticeReport) -> Void = { _ in }

    @State private var showsSettings = false

    private var title: String {
        guard let name = model.profile?.name, !name.isEmpty else { return "Profile" }
        return name
    }

    var body: some View {
        SceneScreen(depth: 0.2) {
            HStack(alignment: .center, spacing: Space.md) {
                Text(title)
                    .font(Typeface.hero(28))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                GlassIconButton(systemImage: "gearshape", size: 44, iconSize: 18, color: Palette.dim, accessibilityLabel: "Settings") {
                    showsSettings = true
                }
            }
            .padding(.top, Space.sm)

            ActivitySections(model: model, onOpenReport: onOpenReport)
                .padding(.top, Space.xxl)
        }
        .refreshable { if let id = model.userID { await model.history.load(userID: id) } }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: model)
                .presentationDragIndicator(.visible)
        }
        .onAppear { Analytics.enter("profile") }
    }
}
