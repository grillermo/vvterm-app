//
//  GhosttyTerminalAccessoryView+iOS.swift
//  VVTerm
//
//  iOS terminal input accessory presentation.
//

import CoreImage
import SwiftUI
import UIKit

// MARK: - Native UIKit Input Accessory View with Glass Effect

final class TerminalInputAccessoryView: UIInputView {
    private static var barHeight: CGFloat { TerminalAccessoryAppearancePolicy.barHeight }
    /// Control row plus the theme-colored gutter below it. Every sizing path
    /// (`init` frame, `intrinsicContentSize`, both `systemLayoutSizeFitting`
    /// overrides) reports this one value. Not private: `TerminalAccessoryBarLayout`
    /// reads it to reserve the same height in the SwiftUI-hosted route chrome.
    /// The gutter is a per-device preference, so this reads current storage;
    /// `TerminalAccessoryBarLayout` observes the same key and invalidates this
    /// view when it changes.
    static var preferredHeight: CGFloat {
        preferredHeight(gutterHeight: CGFloat(TerminalDefaults.storedAccessoryGutterHeight()))
    }

    static func preferredHeight(gutterHeight: CGFloat) -> CGFloat {
        barHeight + TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(gutterHeight)
    }

    /// Holds every control at a fixed height pinned to the top. The space
    /// below it is painted by `backgroundEffectView`, which spans the full
    /// bounds, so nothing can land between the terminal and the controls.
    private let controlsRow = UIView()

    private weak var terminalOwner: GhosttyTerminalView?
    private let onKey: (TerminalKey) -> Void
    private let onCustomAction: (TerminalAccessoryCustomAction) -> Void
    private let onDismissKeyboard: () -> Void
    private var inputSnapshot: TerminalAccessoryInputSnapshot
    private var ctrlActive = false
    private var altActive = false
    private var commandActive = false
    private var shiftActive = false
    private weak var ctrlButton: UIButton?
    private weak var altButton: UIButton?
    private weak var commandButton: UIButton?
    private weak var shiftButton: UIButton?
    private weak var backgroundEffectView: UIVisualEffectView?
    private weak var dynamicItemsStack: UIStackView?
    private var keyRepeatTimer: DispatchSourceTimer?
    private var repeatingKey: TerminalKey?

    #if DEBUG
    private weak var scrollViewForDiagnostics: UIScrollView?

    var diagnosticBackgroundAppearance: String {
        guard let color = backgroundEffectView?.backgroundColor else { return "missing" }
        let resolved = color.resolvedColor(with: traitCollection)
        return isDarkBackgroundColor(resolved) == true ? "dark" : "light"
    }

    var diagnosticOwnerInterfaceStyle: String {
        interfaceStyleDescription(terminalOwner?.traitCollection.userInterfaceStyle ?? .unspecified)
    }

    var diagnosticHostInterfaceStyle: String {
        interfaceStyleDescription(hostInterfaceStyle)
    }

    var diagnosticResolvedInterfaceStyle: String {
        interfaceStyleDescription(resolvedInterfaceStyle)
    }

    var diagnosticHeight: CGFloat {
        bounds.height
    }

    var diagnosticFittingHeight: CGFloat {
        systemLayoutSizeFitting(
            CGSize(width: max(bounds.width, 1), height: 0)
        ).height
    }

    var diagnosticControlsScreenFrame: CGRect? {
        guard let window else { return nil }
        let controlViews: [UIView] = [scrollViewForDiagnostics]
            .compactMap { $0 }
            .filter { !$0.isHidden }
        // Convert each view's own bounds so the result doesn't depend on
        // which superview hosts the controls.
        let framesInWindow = controlViews.map { $0.convert($0.bounds, to: window) }
        guard let first = framesInWindow.first else { return nil }
        let unionInWindow = framesInWindow.dropFirst().reduce(first) { $0.union($1) }
        return window.convert(unionInWindow, to: window.screen.coordinateSpace)
    }

    var diagnosticBackgroundHex: String {
        guard let color = backgroundEffectView?.backgroundColor?
            .resolvedColor(with: traitCollection) else { return "none" }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "none" }
        return String(
            format: "%02X%02X%02X",
            Int((min(max(red, 0), 1) * 255).rounded()),
            Int((min(max(green, 0), 1) * 255).rounded()),
            Int((min(max(blue, 0), 1) * 255).rounded())
        )
    }

    /// Superview chain inside the keyboard host, so test runs show how
    /// UIKit actually placed and sized the accessory.
    var diagnosticHostChain: String {
        var parts: [String] = []
        var view = superview
        while let current = view {
            let frame = current.frame
            parts.append(String(
                format: "%@:%.1f,%.1f,%.1f,%.1f",
                String(describing: type(of: current)),
                frame.minX, frame.minY, frame.width, frame.height
            ))
            view = current.superview
        }
        return parts.isEmpty ? "none" : parts.joined(separator: "|")
    }
    #endif

    init(
        terminalOwner: GhosttyTerminalView,
        inputSnapshot: TerminalAccessoryInputSnapshot,
        onKey: @escaping (TerminalKey) -> Void,
        onCustomAction: @escaping (TerminalAccessoryCustomAction) -> Void,
        onDismissKeyboard: @escaping () -> Void
    ) {
        self.terminalOwner = terminalOwner
        self.inputSnapshot = inputSnapshot
        self.onKey = onKey
        self.onCustomAction = onCustomAction
        self.onDismissKeyboard = onDismissKeyboard
        // The system sizes UIInputView to the active keyboard width; the
        // initial width is only a placeholder.
        super.init(
            frame: CGRect(x: 0, y: 0, width: 320, height: Self.preferredHeight),
            inputViewStyle: .keyboard
        )
        allowsSelfSizing = true
        accessibilityIdentifier = "vvterm.keyboard.accessory"
        setupView()
        observeResolvedAppearanceChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        terminalOwner?.notifyKeyboardAvoidanceAccessoryFrameChange()
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    // UIKit's constraint engine measures self-sizing views through the
    // two-argument variant; the one-argument wrapper delegates here so both
    // paths report the same stable size. A divergent measurement (constraint
    // fallback vs. intrinsic size) lets the keyboard host reserve a slot
    // that disagrees with the accessory's frame, which after a floating-to-
    // docked re-attach leaves the accessory's bottom edge below the key top.
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority _: UILayoutPriority,
        verticalFittingPriority _: UILayoutPriority
    ) -> CGSize {
        let currentWidth = bounds.width.isFinite && bounds.width > 0
            ? bounds.width
            : 1
        let width = targetSize.width.isFinite
            && targetSize.width > 0
            && targetSize.width < UIView.layoutFittingExpandedSize.width
            ? targetSize.width
            : currentWidth
        return CGSize(width: width, height: Self.preferredHeight)
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        stopKeyRepeat()
    }

    private func setupView() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear

        let blur = UIVisualEffectView(effect: nil)
        blur.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(blur, at: 0)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        backgroundEffectView = blur
        updateBackgroundEffect()

        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.backgroundColor = .clear
        addSubview(controlsRow)
        NSLayoutConstraint.activate([
            controlsRow.topAnchor.constraint(equalTo: topAnchor),
            controlsRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsRow.heightAnchor.constraint(equalToConstant: Self.barHeight)
        ])

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        controlsRow.addSubview(scrollView)
        #if DEBUG
        scrollViewForDiagnostics = scrollView
        #endif

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: controlsRow.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: controlsRow.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: controlsRow.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: controlsRow.trailingAnchor)
        ])

        let dynamicStack = UIStackView()
        dynamicStack.translatesAutoresizingMaskIntoConstraints = false
        dynamicStack.axis = .horizontal
        dynamicStack.spacing = 8
        dynamicStack.alignment = .center
        dynamicStack.distribution = .fill
        // Keep intrinsic widths for text buttons and let UIScrollView handle overflow.
        dynamicStack.setContentHuggingPriority(.required, for: .horizontal)
        dynamicStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        scrollView.addSubview(dynamicStack)
        NSLayoutConstraint.activate([
            dynamicStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            dynamicStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            dynamicStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            dynamicStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            dynamicStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -16)
        ])
        dynamicItemsStack = dynamicStack

        rebuildAccessoryItems()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateBackgroundEffect()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBackgroundEffect()
        terminalOwner?.notifyKeyboardAvoidanceAccessoryFrameChange()
    }

    private func updateBackgroundEffect() {
        guard let backgroundEffectView else { return }
        let interfaceStyle = resolvedInterfaceStyle
        let backgroundColor = resolveThemeBackgroundColor(for: interfaceStyle)
            .resolvedColor(with: appearanceTraits(for: interfaceStyle))
        updateInterfaceStyle(for: backgroundColor)
        self.backgroundColor = backgroundColor
        backgroundEffectView.effect = nil
        backgroundEffectView.backgroundColor = backgroundColor
    }

    func refreshAppearance() {
        updateBackgroundEffect()
    }

    func apply(_ snapshot: TerminalAccessoryInputSnapshot) {
        guard snapshot != inputSnapshot else { return }
        inputSnapshot = snapshot
        rebuildAccessoryItems()
    }

    private func updateInterfaceStyle(for backgroundColor: UIColor) {
        if #available(iOS 13.0, *) {
            let resolved = backgroundColor.resolvedColor(with: traitCollection)
            if let isDark = isDarkBackgroundColor(resolved) {
                overrideUserInterfaceStyle = isDark ? .dark : .light
            } else {
                let style = window?.traitCollection.userInterfaceStyle ?? traitCollection.userInterfaceStyle
                overrideUserInterfaceStyle = style == .unspecified ? .unspecified : style
            }
        }
    }

    private func isDarkBackgroundColor(_ color: UIColor) -> Bool? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return TerminalAccessoryAppearancePolicy.isDarkBackground(
                red: red,
                green: green,
                blue: blue
            )
        }

        if #available(iOS 13.0, *) {
            let ciColor = CIColor(color: color)
            return TerminalAccessoryAppearancePolicy.isDarkBackground(
                red: ciColor.red,
                green: ciColor.green,
                blue: ciColor.blue
            )
        }

        return nil
    }

    private func observeResolvedAppearanceChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResolvedAppearanceChange),
            name: Ghostty.configDidReloadNotification,
            object: nil
        )
    }

    @objc private func handleResolvedAppearanceChange() {
        updateBackgroundEffect()
    }

    private func rebuildAccessoryItems() {
        guard let dynamicItemsStack else { return }

        for arrangedSubview in dynamicItemsStack.arrangedSubviews {
            dynamicItemsStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for item in inputSnapshot.resolvedItems {
            switch item {
            case .system(let actionID):
                guard let button = makeSystemActionButton(for: actionID) else { continue }
                dynamicItemsStack.addArrangedSubview(button)
            case .custom(let action):
                let button = makeCustomActionButton(for: action)
                dynamicItemsStack.addArrangedSubview(button)
            }
        }

        clearLatchedModifiersWithoutButtons()
    }

    /// A modifier removed from the layout while latched would keep applying to
    /// the next key with nothing on screen to show it, so drop its state.
    private func clearLatchedModifiersWithoutButtons() {
        if ctrlButton == nil { ctrlActive = false }
        if altButton == nil { altActive = false }
        if commandButton == nil { commandActive = false }
        if shiftButton == nil { shiftActive = false }
    }

    private func makeSystemActionButton(for actionID: TerminalAccessorySystemActionID) -> UIButton? {
        if actionID.isModifier {
            return makeLatchingModifierButton(for: actionID)
        }

        if actionID == .dismissKeyboard {
            let button = makeIconButton(icon: actionID.iconName ?? "keyboard.chevron.compact.down") { [weak self] in
                self?.onDismissKeyboard()
            }
            button.accessibilityLabel = actionID.listTitle
            button.accessibilityIdentifier = "vvterm.keyboard.accessory.hide"
            return button
        }

        guard let terminalKey = actionID.terminalKey else { return nil }

        let button: UIButton
        if let iconName = actionID.iconName {
            if actionID.isRepeatable {
                button = makeRepeatableIconButton(icon: iconName, key: terminalKey)
            } else {
                button = makeIconButton(icon: iconName) { [weak self] in
                    self?.sendKey(terminalKey)
                }
            }
        } else if actionID.isRepeatable {
            button = makeRepeatablePillButton(title: actionID.toolbarTitle, key: terminalKey)
        } else {
            button = makePillButton(title: actionID.toolbarTitle) { [weak self] in
                self?.sendKey(terminalKey)
            }
        }

        button.accessibilityLabel = actionID.listTitle
        button.accessibilityIdentifier = "vvterm.keyboard.accessory.system.\(actionID.rawValue)"
        return button
    }

    /// Modifiers latch instead of sending a key, so the bar keeps their state
    /// and applies it to the next key or custom action it sends.
    private func makeLatchingModifierButton(for actionID: TerminalAccessorySystemActionID) -> UIButton {
        let button = makeModifierButton(title: actionID.toolbarTitle) { [weak self] in
            guard let self else { return }
            switch actionID {
            case .commandModifier: self.commandActive.toggle()
            case .controlModifier: self.ctrlActive.toggle()
            case .alternateModifier: self.altActive.toggle()
            case .shiftModifier: self.shiftActive.toggle()
            default: return
            }
            self.updateModifierState()
        }
        button.accessibilityLabel = actionID.listTitle
        button.accessibilityIdentifier = "vvterm.keyboard.accessory.system.\(actionID.rawValue)"

        let isActive: Bool
        switch actionID {
        case .commandModifier:
            commandButton = button
            isActive = commandActive
        case .controlModifier:
            ctrlButton = button
            isActive = ctrlActive
        case .alternateModifier:
            altButton = button
            isActive = altActive
        default:
            shiftButton = button
            isActive = shiftActive
        }
        updateModifierButton(button, isActive: isActive)
        return button
    }

    private func makeCustomActionButton(for action: TerminalAccessoryCustomAction) -> UIButton {
        let visibleTitle = String(action.title.prefix(12))
        let title = visibleTitle.isEmpty ? action.kind.title : visibleTitle
        let button = makePillButton(title: title) { [weak self] in
            self?.sendCustomAction(action)
        }
        button.accessibilityLabel = action.title
        button.accessibilityIdentifier = "vvterm.keyboard.accessory.custom.\(action.id.uuidString)"
        return button
    }

    private var resolvedInterfaceStyle: UIUserInterfaceStyle {
        let ownerStyle = terminalOwner?.traitCollection.userInterfaceStyle ?? .unspecified
        let resolved = TerminalAccessoryAppearancePolicy.resolvedInterfaceStyle(
            owner: policyInterfaceStyle(ownerStyle),
            host: policyInterfaceStyle(hostInterfaceStyle)
        )
        switch resolved {
        case .unspecified:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var hostInterfaceStyle: UIUserInterfaceStyle {
        #if DEBUG
        if Foundation.ProcessInfo.processInfo.arguments.contains(
            "--vvterm-ui-test-detached-light-accessory-host"
        ) {
            return .light
        }
        #endif
        return traitCollection.userInterfaceStyle
    }

    private func policyInterfaceStyle(
        _ style: UIUserInterfaceStyle
    ) -> TerminalAccessoryAppearancePolicy.InterfaceStyle {
        switch style {
        case .light:
            return .light
        case .dark:
            return .dark
        default:
            return .unspecified
        }
    }

    #if DEBUG
    private func interfaceStyleDescription(_ style: UIUserInterfaceStyle) -> String {
        switch style {
        case .light:
            return "light"
        case .dark:
            return "dark"
        default:
            return "unspecified"
        }
    }
    #endif

    private func appearanceTraits(
        for interfaceStyle: UIUserInterfaceStyle
    ) -> UITraitCollection {
        guard interfaceStyle != .unspecified else { return traitCollection }
        return UITraitCollection(traitsFrom: [
            traitCollection,
            UITraitCollection(userInterfaceStyle: interfaceStyle)
        ])
    }

    private func resolveThemeBackgroundColor(
        for interfaceStyle: UIUserInterfaceStyle
    ) -> UIColor {
        if let snapshot = terminalOwner?.ghosttyAppWrapper?.appearanceSnapshot {
            let appearance: TerminalColorAppearance = interfaceStyle == .dark ? .dark : .light
            let backgroundHex = snapshot.theme(for: appearance).palette.backgroundHex
            return UIColor(Color.fromHex(backgroundHex))
        }
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .systemBackground
        }
    }

    private func makePillButton(title: String, onTap: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .center
        button.clipsToBounds = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
            config.attributedTitle = AttributedString(
                title,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)])
            )
            config.baseForegroundColor = .label
            button.configuration = config
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.setTitleColor(.label, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        }
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.06)
        }
        button.layer.cornerRadius = 16
        button.addAction(UIAction { _ in
            onTap()
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 32)
        ])

        return button
    }

    private func makeRepeatablePillButton(title: String, key: TerminalKey) -> UIButton {
        let button = RepeatableKeyButton(type: .system)
        button.key = key
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .center
        button.clipsToBounds = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
            config.attributedTitle = AttributedString(
                title,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)])
            )
            config.baseForegroundColor = .label
            button.configuration = config
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.setTitleColor(.label, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        }
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.06)
        }
        button.layer.cornerRadius = 16

        button.addTarget(self, action: #selector(repeatButtonDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchUpOutside)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchCancel)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchDragExit)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 32)
        ])

        return button
    }

    private func makeIconButton(icon: String, onTap: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.06)
        }
        button.layer.cornerRadius = 16
        button.addAction(UIAction { _ in
            onTap()
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])

        return button
    }

    private func makeRepeatableIconButton(icon: String, key: TerminalKey) -> UIButton {
        let button = RepeatableKeyButton(type: .system)
        button.key = key
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.06)
        }
        button.layer.cornerRadius = 16

        button.addTarget(self, action: #selector(repeatButtonDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchUpOutside)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchCancel)
        button.addTarget(self, action: #selector(repeatButtonUp(_:)), for: .touchDragExit)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])

        return button
    }

    private func makeModifierButton(title: String, onTap: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .center
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            config.attributedTitle = AttributedString(
                title,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 13, weight: .semibold)])
            )
            config.baseForegroundColor = .secondaryLabel
            button.configuration = config
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.setTitleColor(.secondaryLabel, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        }
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.black.withAlphaComponent(0.04)
        }
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        button.addAction(UIAction { _ in
            onTap()
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 28),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])

        return button
    }

    private func sendKey(_ key: TerminalKey) {
        var modifiedKey = key
        if ctrlActive {
            modifiedKey = modifiedKey.withCtrl()
        }
        if altActive {
            modifiedKey = modifiedKey.withAlt()
        }
        if commandActive {
            modifiedKey = modifiedKey.withCommand()
        }
        if shiftActive {
            modifiedKey = modifiedKey.withShift()
        }
        if ctrlActive || altActive || commandActive || shiftActive {
            ctrlActive = false
            altActive = false
            commandActive = false
            shiftActive = false
            updateModifierState()
        }
        onKey(modifiedKey)
    }

    private func sendCustomAction(_ action: TerminalAccessoryCustomAction) {
        if ctrlActive || altActive || commandActive || shiftActive {
            ctrlActive = false
            altActive = false
            commandActive = false
            shiftActive = false
            updateModifierState()
        }
        onCustomAction(action)
    }

    @objc private func repeatButtonDown(_ sender: RepeatableKeyButton) {
        startKeyRepeat(for: sender.key)
    }

    @objc private func repeatButtonUp(_ sender: RepeatableKeyButton) {
        stopKeyRepeat()
    }

    private func startKeyRepeat(for key: TerminalKey) {
        stopKeyRepeat()
        repeatingKey = key
        sendKey(key)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.35, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self = self, let repeatingKey = self.repeatingKey else { return }
            self.sendKey(repeatingKey)
        }
        keyRepeatTimer = timer
        timer.resume()
    }

    private func stopKeyRepeat() {
        keyRepeatTimer?.cancel()
        keyRepeatTimer = nil
        repeatingKey = nil
    }

    func consumeModifiers() -> (ctrl: Bool, alt: Bool, command: Bool, shift: Bool) {
        let ctrl = ctrlActive
        let alt = altActive
        let command = commandActive
        let shift = shiftActive
        if ctrl || alt || command || shift {
            ctrlActive = false
            altActive = false
            commandActive = false
            shiftActive = false
            updateModifierState()
        }
        return (ctrl, alt, command, shift)
    }

    #if DEBUG
    func keyboardUITestSetModifiers(_ modifiers: TerminalAccessoryShortcutModifiers) {
        ctrlActive = modifiers.control
        altActive = modifiers.alternate
        commandActive = modifiers.command
        shiftActive = modifiers.shift
        updateModifierState()
    }
    #endif

    private func updateModifierState() {
        UIView.animate(withDuration: 0.2) {
            self.updateModifierButton(self.ctrlButton, isActive: self.ctrlActive)
            self.updateModifierButton(self.altButton, isActive: self.altActive)
            self.updateModifierButton(self.commandButton, isActive: self.commandActive)
            self.updateModifierButton(self.shiftButton, isActive: self.shiftActive)
        }
    }

    private func updateModifierButton(_ button: UIButton?, isActive: Bool) {
        guard let button else { return }
        if isActive {
            button.backgroundColor = .systemBlue
            button.layer.borderColor = UIColor.clear.cgColor
            if #available(iOS 15.0, *), var config = button.configuration {
                config.baseForegroundColor = .white
                button.configuration = config
            } else {
                button.setTitleColor(.white, for: .normal)
            }
        } else {
            button.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.08)
                    : UIColor.black.withAlphaComponent(0.04)
            }
            button.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
            if #available(iOS 15.0, *), var config = button.configuration {
                config.baseForegroundColor = .secondaryLabel
                button.configuration = config
            } else {
                button.setTitleColor(.secondaryLabel, for: .normal)
            }
        }
    }

}

private final class RepeatableKeyButton: UIButton {
    var key: TerminalKey = .backspace
}
