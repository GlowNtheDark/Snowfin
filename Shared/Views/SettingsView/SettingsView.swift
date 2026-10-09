//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

struct SettingsView: View {

    #if os(iOS)
    @Default(.userAppearance)
    private var appearance
    #endif

    @Default(.userAccentColor)
    private var accentColor

    #if os(tvOS)
    @Default(.appFontChoice)
    private var appFontChoice

    @State
    private var isAppFontMenuPresented = false

    @FocusState
    private var appFontFocusTarget: AppFontFocusTarget?

    @Namespace
    private var appFontFocusScope
    #endif

    @Default(.VideoPlayer.videoPlayerType)
    private var videoPlayerType

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @Router
    private var router

    @StateObject
    private var viewModel = SettingsViewModel()

    // MARK: - Body

    @ViewBuilder
    var body: some View {
        #if os(tvOS)
        Form {
            serverSection
            videoPlayerSection
            customizeSection
            diagnosticsSection
        } image: {
            Image(.screenTvOSMark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 400)
        }
        .background {
            SnowfinSettingsBackground()
        }
        .overlayPreferenceValue(AppFontMenuAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if isAppFontMenuPresented, let anchor {
                    let rowFrame = geometry[anchor]
                    AppFontChoiceMenu(
                        selection: $appFontChoice,
                        focusedTarget: $appFontFocusTarget,
                        dismiss: dismissAppFontMenu
                    )
                    .focusScope(appFontFocusScope)
                    .focusSection()
                    .position(x: rowFrame.maxX - 160, y: rowFrame.midY)
                    .zIndex(1)
                }
            }
        }
        .onExitCommand {
            guard isAppFontMenuPresented else { return }
            dismissAppFontMenu()
        }
        #else
        Form(image: .jellyfinBlobBlue) {
            serverSection
            videoPlayerSection
            customizeSection
            diagnosticsSection
        }
        #if os(iOS)
        .navigationTitle(L10n.settings)
        .navigationBarCloseButton {
            router.dismiss()
        }
        #endif
        #endif
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        if let userSession = viewModel.userSession {
            Section {
                UserProfileRow(user: userSession.user.data) {
                    router.route(to: .localUserSettings(user: userSession.user.data))
                }

                ChevronButton(
                    L10n.server,
                    action: {
                        router.route(to: .editLocalServer(server: userSession.server))
                    }
                ) {
                    Label {
                        Text(userSession.server.name)
                    } icon: {
                        if !userSession.server.isVersionCompatible {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                    }
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }

                #if os(iOS)
                if userSession.user.data.policy?.isAdministrator == true {
                    ChevronButton(L10n.dashboard) {
                        router.route(to: .adminDashboard)
                    }
                }
                #endif
            }
        }

        Section {
            Button {
                Task { @MainActor in
                    UIDevice.impact(.medium)
                    await userSessionManager.signOut(reason: .explicit)
                    router.dismiss()
                }
            } label: {
                Text(L10n.switchUser)
                    .frame(maxWidth: .infinity)
                    // Otherwise non-Liquid Glass only uses text height
                    .if(!UIDevice.supportsLiquidGlass) { button in
                        button
                            .frame(maxHeight: .infinity)
                    }
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            #if os(iOS)
                .listRowSeparator(.hidden)
            #endif
                .fontWeight(.semibold)
                .backport
                .buttonStyle(.glassProminent.shadow(false))
                .tint(accentColor)
            #if os(iOS)
                .controlSize(.large)
            #endif
        }
    }

    // MARK: - Video Player Section

    @ViewBuilder
    private var videoPlayerSection: some View {
        Section(L10n.videoPlayer) {
            #if os(iOS)
            Picker(L10n.videoPlayerType, selection: $videoPlayerType)
            #else
            ListRowMenu(L10n.videoPlayerType, selection: $videoPlayerType)
            #endif

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .videoPlayerSettings)
            }

            ChevronButton(L10n.playbackQuality) {
                router.route(to: .playbackQualitySettings)
            }
        } learnMore: {
            LabeledContent(
                L10n.applicationBrand,
                value: L10n.playerSwiftfinDescription
            )
            LabeledContent(
                L10n.native,
                value: L10n.playerNativeDescription
            )
        }
    }

    // MARK: - Customization Section

    @ViewBuilder
    private var customizeSection: some View {
        Section {
            #if os(iOS)
            Picker(L10n.appearance, selection: $appearance)
            #endif

            ColorPicker(L10n.accentColor, selection: $accentColor, supportsOpacity: false)

            #if os(tvOS)
            AppFontSelectionRow(
                selection: $appFontChoice,
                isMenuPresented: $isAppFontMenuPresented,
                focusedTarget: $appFontFocusTarget
            )
            #endif

            ChevronButton(L10n.advanced) {
                router.route(to: .customizeSettingsView)
            }
        } header: {
            Text(L10n.customize)
        } footer: {
            Text(L10n.viewsMayRequireRestart)
        }
    }

    // MARK: - Diagnostics Section

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {

            if ExperimentalSettingsView.isEnabled {
                ChevronButton(L10n.experimental) {
                    router.route(to: .experimentalSettings)
                }
            }

            ChevronButton(L10n.logs) {
                router.route(to: .log)
            }

            #if DEBUG
            ChevronButton("Debug") {
                router.route(to: .debugSettings)
            }
            #endif
        }
    }

    #if os(tvOS)
    private func dismissAppFontMenu() {
        isAppFontMenuPresented = false
        appFontFocusTarget = .row
    }
    #endif
}

#if os(tvOS)
private enum AppFontFocusTarget: Hashable {
    case row
    case choice(AppFontChoice)
}

private struct AppFontMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct AppFontSelectionRow: View {

    @Binding
    var selection: AppFontChoice

    @Binding
    var isMenuPresented: Bool

    var focusedTarget: FocusState<AppFontFocusTarget?>.Binding

    private var isRowFocused: Bool {
        focusedTarget.wrappedValue == .row
    }

    var body: some View {
        Button {
            isMenuPresented = true
            focusedTarget.wrappedValue = nil
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .focused(focusedTarget, equals: .row)
        .listRowInsets(.zero)
        .listRowBackground(Color.clear)
        .anchorPreference(key: AppFontMenuAnchorKey.self, value: .bounds) { $0 }
    }

    @ViewBuilder
    private var rowLabel: some View {
        if UIDevice.supportsLiquidGlass {
            labelView
                .glassEffect(
                    .regular.tint(isRowFocused ? .white : nil),
                    in: .rect
                )
                .scaleEffect(x: isRowFocused ? 1.01 : 1.0, y: isRowFocused ? 1.05 : 1.0, anchor: .center)
                .animation(.easeInOut(duration: 0.125), value: isRowFocused)
        } else {
            labelView
                .background {
                    ZStack {
                        Rectangle()
                            .fill(isRowFocused ? Color.white : Color.clear)

                        if isRowFocused {
                            Rectangle()
                                .fill(Color.white.opacity(0.8))
                                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                        }
                    }
                }
                .scaleEffect(x: isRowFocused ? 1.01 : 1.0, y: isRowFocused ? 1.05 : 1.0, anchor: .center)
                .animation(.easeInOut(duration: 0.125), value: isRowFocused)
        }
    }

    private var labelView: some View {
        HStack {
            Text(L10n.appFont)
                .foregroundStyle(isRowFocused ? .black : .white)
                .padding(.leading, 4)

            Spacer()

            Text(selection.displayTitle)
                .foregroundStyle(isRowFocused ? .black : .secondary)
                .brightness(isRowFocused ? 0.4 : 0)

            Image(systemName: "chevron.up.chevron.down")
                .font(.body)
                .fontWeight(.regular)
                .foregroundStyle(isRowFocused ? .black : .secondary)
                .brightness(isRowFocused ? 0.4 : 0)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct AppFontChoiceMenu: View {

    @Binding
    var selection: AppFontChoice

    var focusedTarget: FocusState<AppFontFocusTarget?>.Binding

    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AppFontChoice.allCases, id: \.self) { choice in
                Button {
                    selection = choice
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(choice.displayTitle)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 16)

                        if choice == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(focusedTarget.wrappedValue == .choice(choice) ? .black : .white)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background {
                        if focusedTarget.wrappedValue == .choice(choice) {
                            Capsule().fill(Color.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .focused(focusedTarget, equals: .choice(choice))
                .onExitCommand(perform: dismiss)
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            }
        }
        .padding(8)
        .frame(width: 320)
        .background(Color.snowfinDeepNavy.opacity(0.98), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .focusSection()
        .defaultFocus(focusedTarget, .choice(selection), priority: .userInitiated)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            focusedTarget.wrappedValue = .choice(selection)
        }
    }
}

private struct SnowfinSettingsBackground: View {

    var body: some View {
        ZStack {
            Color.snowfinDeepNavy

            RadialGradient(
                colors: [
                    Color.snowfinIceBlue.opacity(0.14),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
#endif
