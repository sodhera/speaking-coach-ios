import SwiftUI

/// Account details and practice preferences. Rehearsal activity lives in Progress.
struct ProfileView: View {
    let model: AppModel

    @State private var showsSettings = false
    @State private var showsRoutine = false

    var body: some View {
        NavigationStack {
            SceneScreen {
                HStack(alignment: .center) {
                    Text("Profile")
                        .font(Typeface.hero(30))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    GlassIconButton(systemImage: "gearshape", size: 48, iconSize: 20, color: Palette.dim, accessibilityLabel: "Settings") {
                        showsSettings = true
                    }
                }
                .padding(.top, Space.md)

                if let profile = model.profile {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Kicker(text: "Your account")
                        Text(profile.name.isEmpty ? "Speaking Coach" : profile.name)
                            .font(Typeface.title(21))
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.top, Space.xxl)

                    if profile.moment != nil {
                        HStack(alignment: .top, spacing: Space.md) {
                            GlassRowIcon(icon: "sparkles")
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("A good next step")
                                    .font(Typeface.label(16))
                                    .foregroundStyle(Palette.ink)
                                Text(profile.pattern.fix)
                                    .font(Typeface.body(14))
                                    .foregroundStyle(Palette.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Space.lg)
                        .glassSurface(cornerRadius: Corner.lg)
                        .padding(.top, Space.xxl)
                    }
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Practice preferences")
                        .font(Typeface.title(21))
                        .foregroundStyle(Palette.ink)
                    Button { showsRoutine = true } label: {
                        HStack(spacing: Space.md) {
                            GlassRowIcon(icon: "alarm.fill")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Practice routine")
                                    .font(Typeface.label(16))
                                    .foregroundStyle(Palette.ink)
                                Text("Daily prompt and speak to unlock")
                                    .font(Typeface.body(13))
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.faint)
                        }
                        .padding(Space.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassSurface(cornerRadius: Corner.lg, interactive: true)
                }
                .padding(.top, Space.xxxl)
            }
            .navigationDestination(isPresented: $showsRoutine) {
                RoutineView(routine: model.routine, language: model.profile?.language ?? "en", onBack: { showsRoutine = false })
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: model)
                .presentationDragIndicator(.visible)
        }
        .onAppear { Analytics.enter("profile") }
    }
}
