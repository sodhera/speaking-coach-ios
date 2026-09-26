import SwiftUI

/// The first screen, before a single other word: which language the app
/// speaks. Everything follows from it: every screen, the voice partner, the
/// feedback, the reminders. Nothing is chosen for the user; the phone's own
/// language leads the list, and the screen's own words switch to whichever
/// language is tapped, so the choice reads back in its own voice.
struct LanguagePickerView: View {
    let onChoose: (String) -> Void

    @State private var selected: String?

    /// What the screen speaks while nothing is confirmed.
    private var speaking: String { selected ?? AppLanguage.deviceLanguage }

    private var ordered: [String] {
        let device = AppLanguage.deviceLanguage
        return [device] + AppLanguage.supported.filter { $0 != device }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: Space.xxl) {
                        VStack(spacing: Space.md) {
                            BrandMark(size: 64)
                            Text(AppLanguage.string("Choose your language", in: speaking))
                                .font(Typeface.title(26))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                            Text(AppLanguage.string("The app, your practice partner and your feedback will all speak it.", in: speaking))
                                .font(Typeface.body(15))
                                .foregroundStyle(Palette.dim)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .animation(.easeInOut(duration: 0.2), value: speaking)

                        GlassGroup(spacing: Space.md) {
                            VStack(spacing: Space.md) {
                                ForEach(ordered, id: \.self) { code in
                                    OptionRow(icon: nil, title: AppLanguage.autonym(code), isSelected: selected == code) {
                                        selected = code
                                    }
                                    .environment(\.layoutDirection, code == "ar" ? .rightToLeft : .leftToRight)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height - Space.xxxl, alignment: .top)
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.xxxl)
                    .padding(.bottom, Space.xl)
                }
                .scrollIndicators(.hidden)
                .bottomEdgeFade()
            }

            PrimaryButton(title: AppLanguage.string("Continue", in: speaking)) {
                guard let selected else { return }
                onChoose(selected)
            }
            .disabled(selected == nil)
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.lg)
        }
        .onAppear { Analytics.enter("language") }
    }
}
