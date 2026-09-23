import StoreKit
import SwiftUI

/// Settings as a sheet over Profile: a hero title with the close ✕, then
/// grouped glass rows. Rows name things; they don't explain them.
struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var notice: String?
    @State private var confirmingSignOut = false
    @State private var deleting = false
    @State private var remindersOn = Reminders.isEnabled

    private var subscriptions: Subscriptions { model.subscriptions }

    var body: some View {
        SceneScreen(depth: 0.1) {
            HStack {
                Text("Settings")
                    .font(Typeface.hero(28))
                    .foregroundStyle(Palette.ink)
                Spacer()
                GlassIconButton(systemImage: "xmark", size: 56, iconSize: 18, color: Palette.dim, accessibilityLabel: "Close") { dismiss() }
            }
            .padding(.top, Space.lg)

            VStack(alignment: .leading, spacing: Space.xxl) {
                section("Account") {
                    GlassRow(icon: "person.fill", title: model.profile?.name.isEmpty == false ? model.profile!.name : "Your account", value: model.email)
                }

                section("Subscription") {
                    GlassRow(icon: "sparkles", title: "Speaking Coach", value: subscriptionStatus)
                    GlassRowDivider()
                    rowButton(GlassRow(icon: "creditcard", title: "Manage subscription", showsChevron: true)) { manage() }
                    GlassRowDivider()
                    rowButton(GlassRow(icon: "arrow.clockwise", title: "Restore purchases", showsChevron: true)) {
                        Task { notice = await subscriptions.restore().message }
                    }
                }

                section("Practice") {
                    Menu {
                        Picker("Practice language", selection: Binding(
                            get: { model.profile?.language ?? "en" },
                            set: { model.updateLanguage($0) }
                        )) {
                            ForEach(PracticeLanguage.all) { Text($0.name).tag($0.id) }
                        }
                    } label: {
                        GlassRow(icon: "globe", title: "Language", value: PracticeLanguage.named(model.profile?.language ?? "en"), showsChevron: true)
                    }
                    GlassRowDivider()
                    HStack(spacing: Space.md) {
                        GlassRowIcon(icon: "bell.fill")
                        Toggle(isOn: Binding(
                            get: { remindersOn },
                            set: { on in
                                Haptics.heavy()
                                if on {
                                    Task {
                                        let title = PracticeCatalog.definition(model.profile?.moment?.firstPracticeID ?? "")?.title
                                        remindersOn = await Reminders.enable(practiceTitle: title)
                                        if !remindersOn { notice = "Turn on notifications for Speaking Coach in the Settings app." }
                                    }
                                } else {
                                    Reminders.disable()
                                    remindersOn = false
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Daily reminder").font(Typeface.body(16)).foregroundStyle(Palette.ink)
                                Text(Reminders.timeLabel).font(Typeface.body(13)).foregroundStyle(Palette.muted)
                            }
                        }
                        .tint(Palette.coral)
                    }
                    .padding(.vertical, Space.md)
                }

                section("About") {
                    rowButton(GlassRow(icon: "hand.raised.fill", title: "Privacy policy", showsChevron: true)) { UIApplication.shared.open(AppConfig.privacyURL) }
                    GlassRowDivider()
                    rowButton(GlassRow(icon: "doc.text.fill", title: "Terms of use", showsChevron: true)) { UIApplication.shared.open(AppConfig.termsURL) }
                }

                if let notice {
                    Text(notice).font(Typeface.body(14)).foregroundStyle(Palette.coralDeep)
                }

                VStack(spacing: Space.sm) {
                    SecondaryButton(title: "Sign out") { confirmingSignOut = true }
                    QuietButton(title: "Delete account", color: Palette.danger) { deleting = true }
                }

                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, Space.xxl)
        }
        .confirmationDialog("Sign out of Speaking Coach?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                dismiss()
                Task { await model.signOut() }
            }
        }
        .sheet(isPresented: $deleting) {
            DeleteAccountSheet(model: model)
                .presentationDetents([.medium])
        }
        .onAppear { Analytics.enter("settings") }
    }

    private var subscriptionStatus: String {
        switch subscriptions.access {
        case .entitled:
            guard let date = subscriptions.expiration else { return "Active" }
            let day = date.formatted(.dateTime.month(.abbreviated).day())
            return subscriptions.willRenew ? "Renews \(day)" : "Ends \(day)"
        case .notEntitled: return "Not active"
        case .unknown: return "Checking…"
        }
    }

    private func manage() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }

    private func rowButton(_ row: GlassRow, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.heavy()
            action()
        } label: { row }
            .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Kicker(text: title)
            GlassRowGroup { content() }
        }
    }
}

/// Deleting is permanent, so it takes a typed word — the same contract the
/// server's `/api/delete-account` checks.
private struct DeleteAccountSheet: View {
    let model: AppModel

    @State private var typed = ""
    @State private var working = false
    @State private var error: String?

    private let word = "DELETE"
    private var matches: Bool { typed.trimmingCharacters(in: .whitespaces).uppercased() == word }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Delete your account?")
                .font(Typeface.hero(26))
                .foregroundStyle(Palette.ink)
            Text("Your plan, practice history and feedback are erased. This can't be undone. Cancel your subscription in the App Store separately.")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", text: $typed, prompt: Text("Type \(word) to confirm").foregroundStyle(Palette.muted))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(Typeface.label(17))
                .padding(.horizontal, Space.lg)
                .frame(height: 54)
                .glassSurface(cornerRadius: Corner.md, interactive: true)
            if let error {
                Text(error).font(Typeface.body(14)).foregroundStyle(Palette.danger)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.heavy()
                Task { await delete() }
            } label: {
                ZStack {
                    Text("Delete account").opacity(working ? 0 : 1)
                    if working { ProgressView().tint(.white) }
                }
                .font(Typeface.label(17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(Palette.danger))
            }
            .buttonStyle(.plain)
            .disabled(!matches || working)
            .opacity(matches ? 1 : 0.45)
        }
        .padding(Space.xxl)
        .background(Palette.paper)
    }

    private func delete() async {
        working = true
        error = nil
        do {
            try await model.deleteAccount(confirmation: typed)
        } catch {
            self.error = error.localizedDescription
            working = false
        }
    }
}
