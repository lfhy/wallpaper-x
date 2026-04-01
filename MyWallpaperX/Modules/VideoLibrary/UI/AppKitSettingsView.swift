//
//  AppKitSettingsView.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct AppKitSettingsView: NSViewRepresentable {
    @EnvironmentObject var wallpaperManager: WallpaperManager

    func makeNSView(context: Context) -> AppKitSettingsContainerView {
        // SwiftUI 只负责把 AppKit 容器挂进来，设置页状态和交互都由容器自己维护。
        AppKitSettingsContainerView(wallpaperManager: wallpaperManager)
    }

    func updateNSView(_ nsView: AppKitSettingsContainerView, context: Context) {
        nsView.refreshFromState()
    }
}

final class AppKitSettingsContainerView: NSView {
    private let wallpaperManager: WallpaperManager
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingUI = false
    private var scrollToTopObserver: NSObjectProtocol?
    private var isScrollToTopAnimating = false
    private var restingScrollOrigin: NSPoint?

    private let scrollView: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = false
        view.autohidesScrollers = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let documentView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .gravityAreas
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let playbackSection = SettingsGroupView(title: "播放控制")
    private let systemSection = SettingsGroupView(title: "系统行为")
    private let performanceSection = SettingsGroupView(title: "性能设置")
    private let displaySection = SettingsGroupView(title: "显示设置")
    private let profileSettingsSection = SettingsGroupView(title: nil)
    private let clearCacheSection = SettingsGroupView(title: nil)
    private let resetSettingsSection = SettingsGroupView(title: nil)

    private let loopSwitch = NSSwitch()
    private let randomSwitch = NSSwitch()
    private let sequentialSwitch = NSSwitch()
    private let autoSwitchSwitch = NSSwitch()
    private let intervalField = NSTextField()
    private let timeUnitPopup = NSPopUpButton()
    private var intervalRowView: NSView?
    private var autoSwitchRowView: NSView?
    private let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let volumeValueLabel = NSTextField(labelWithString: "50%")
    private let muteSwitch = NSSwitch()

    private let playbackRateSlider = NSSlider(value: 1.0, minValue: 0.25, maxValue: 2.0, target: nil, action: nil)
    private let playbackRateValueLabel = NSTextField(labelWithString: "1.0x")
    private let playbackRateSwitch = NSSwitch()
    private var playbackRateRowView: NSView?

    private let startOnBootSwitch = NSSwitch()
    private let syncSystemWallpaperSwitch = NSSwitch()
    private let systemHotkeysSwitch = NSSwitch()
    private let hotkeyRowsStack = NSStackView()
    private var hotkeyRowsContainer: NSView?
    private var hotkeyEnableSwitches: [SystemHotkeyAction: NSSwitch] = [:]
    private var hotkeyPopups: [SystemHotkeyAction: NSPopUpButton] = [:]

    private let pauseOtherAppFocusedSwitch = NSSwitch()
    private let pauseOtherAppFullscreenSwitch = NSSwitch()
    private let pauseWhenUnpluggedSwitch = NSSwitch()
    private let pauseWhenIdleSwitch = NSSwitch()
    private let idleTimeoutPopup = NSPopUpButton()
    private var idleTimeoutRowView: NSView?

    private let multiDisplaySwitch = NSSwitch()
    private let fillModeFitButton = NSButton(radioButtonWithTitle: VideoFillMode.aspectFit.rawValue, target: nil, action: nil)
    private let fillModeFillButton = NSButton(radioButtonWithTitle: VideoFillMode.aspectFill.rawValue, target: nil, action: nil)

    private let clearCacheButton = NSButton(title: "清空所有缓存", target: nil, action: nil)
    private let resetSettingsButton = NSButton(title: "重置为默认设置", target: nil, action: nil)
    private let exportProfileButton = NSButton(title: "导出个人设置", target: nil, action: nil)
    private let importProfileButton = NSButton(title: "导入个人设置", target: nil, action: nil)

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        super.init(frame: .zero)
        setupLayout()
        setupSections()
        applyNativeControlSizes()
        bindEvents()
        observeManager()
        observeScrollToTopRequests()
        refreshFromState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        scheduleRestingScrollOriginCapture()
    }

    deinit {
        if let scrollToTopObserver {
            NotificationCenter.default.removeObserver(scrollToTopObserver)
        }
    }

    func refreshFromState() {
        // 这是设置页的单一回填入口：所有控件状态都从 manager 快照回填，避免局部控件自己保留旧态。
        isUpdatingUI = true
        defer { isUpdatingUI = false }

        let settings = wallpaperManager.settings

        loopSwitch.state = settings.loopPlayback ? .on : .off
        randomSwitch.state = settings.randomPlayback ? .on : .off
        sequentialSwitch.state = settings.sequentialPlayback ? .on : .off

        let autoSwitchAvailable = settings.randomPlayback || settings.sequentialPlayback
        autoSwitchSwitch.state = settings.autoSwitchEnabled ? .on : .off
        autoSwitchSwitch.isEnabled = autoSwitchAvailable
        // 循环播放模式下隐藏自动切换整行（含间隔时间），其他模式下显示。
        autoSwitchRowView?.isHidden = !autoSwitchAvailable
        intervalRowView?.isHidden = !(settings.autoSwitchEnabled && autoSwitchAvailable)
        intervalField.isEnabled = autoSwitchAvailable && settings.autoSwitchEnabled
        timeUnitPopup.isEnabled = autoSwitchAvailable && settings.autoSwitchEnabled
        intervalField.stringValue = "\(max(1, settings.randomInterval))"
        selectTimeUnit(settings.timeUnit)

        let clampedVolume = Int(max(0, min(100, round(settings.volume))))
        volumeSlider.doubleValue = Double(clampedVolume)
        volumeValueLabel.stringValue = "\(clampedVolume)%"
        muteSwitch.state = wallpaperManager.isMuted ? .on : .off

        let clampedRate = max(0.25, min(2.0, settings.playbackRate))
        playbackRateSwitch.state = settings.playbackRateEnabled ? .on : .off
        playbackRateSlider.doubleValue = clampedRate
        playbackRateValueLabel.stringValue = String(format: "%.2gx", clampedRate)
        // 开关关闭时隐藏滑块和数值标签，只保留开关本身。
        playbackRateSlider.isHidden = !settings.playbackRateEnabled
        playbackRateValueLabel.isHidden = !settings.playbackRateEnabled

        startOnBootSwitch.state = settings.startOnBoot ? .on : .off
        syncSystemWallpaperSwitch.state = settings.syncSystemWallpaper ? .on : .off
        systemHotkeysSwitch.state = settings.systemHotkeysEnabled ? .on : .off
        hotkeyRowsContainer?.isHidden = !settings.systemHotkeysEnabled

        pauseOtherAppFocusedSwitch.state = settings.pauseWhenOtherAppFocused ? .on : .off
        pauseOtherAppFullscreenSwitch.state = settings.pauseWhenOtherAppFullscreen ? .on : .off
        pauseWhenUnpluggedSwitch.state = settings.pauseWhenUnplugged ? .on : .off
        pauseWhenIdleSwitch.state = settings.pauseWhenIdle ? .on : .off
        idleTimeoutRowView?.isHidden = !settings.pauseWhenIdle
        selectIdleTimeout(settings.idleTimeoutMinutes)

        multiDisplaySwitch.state = settings.multiDisplayEnabled ? .on : .off
        selectFillMode(settings.videoFillMode)

        refreshHotkeyRows()
        scheduleRestingScrollOriginCapture()
    }

    private func setupLayout() {
        // 外层滚动视图是必须的，因为设置页内容会在高密度选项下超过窗口高度。
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.documentView = documentView
        addSubview(scrollView)
        documentView.addSubview(contentStack)

        let preferredWidth = contentStack.widthAnchor.constraint(equalToConstant: 500)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
            contentStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -24),
            contentStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            preferredWidth
        ])
    }

    private func observeScrollToTopRequests() {
        scrollToTopObserver = NotificationCenter.default.addObserver(
            forName: .appKitRequestScrollToTopForCurrentSelection,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.scrollToTop(animated: true)
        }
    }

    private func scrollToTop(animated: Bool) {
        guard !isScrollToTopAnimating else { return }
        guard scrollView.documentView != nil else { return }

        let targetOrigin = restingScrollOrigin ?? NSPoint(x: 0, y: 0)
        guard scrollView.contentView.bounds.origin != targetOrigin else { return }

        isScrollToTopAnimating = true
        NotificationCenter.default.post(name: .appKitLibraryGridScrollToTopAnimationWillStart, object: nil)
        NSAnimationContext.runAnimationGroup { context in
            let distance = abs(scrollView.contentView.bounds.origin.y - targetOrigin.y)
            context.duration = animated ? min(0.36, max(0.20, distance / 5200.0)) : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.85, 0.20, 1.0)
            scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.isScrollToTopAnimating = false
            NotificationCenter.default.post(name: .appKitLibraryGridScrollToTopAnimationDidEnd, object: nil)
        }
    }

    private func scheduleRestingScrollOriginCapture() {
        guard restingScrollOrigin == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.restingScrollOrigin == nil else { return }
            self.layoutSubtreeIfNeeded()
            self.scrollView.layoutSubtreeIfNeeded()
            self.documentView.layoutSubtreeIfNeeded()
            self.captureRestingScrollOriginIfNeeded()
        }
    }

    private func captureRestingScrollOriginIfNeeded() {
        guard restingScrollOrigin == nil else { return }
        guard window != nil, scrollView.documentView != nil else { return }
        restingScrollOrigin = scrollView.contentView.bounds.origin
    }

    private func setupSections() {
        // 分组顺序固定：播放、系统、性能、显示、维护，避免重排后影响用户心智和回归判断。
        setupPlaybackSection()
        setupSystemSection()
        setupPerformanceSection()
        setupDisplaySection()
        setupMaintenanceSection()

        addSection(playbackSection)
        addSection(systemSection)
        addSection(performanceSection)
        addSection(displaySection)
        let maintenanceSpacer = NSView()
        maintenanceSpacer.translatesAutoresizingMaskIntoConstraints = false
        maintenanceSpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        contentStack.addArrangedSubview(maintenanceSpacer)
        addSection(profileSettingsSection)
        addSection(clearCacheSection)
        addSection(resetSettingsSection)
    }

    private func addSection(_ section: NSView) {
        contentStack.addArrangedSubview(section)
        section.translatesAutoresizingMaskIntoConstraints = false
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func setupPlaybackSection() {
        // 播放控制区只放与播放状态相关的可逆配置，避免和系统集成配置混在一起。
        playbackSection.addRow(makeSettingRow(title: "循环播放", trailing: loopSwitch))
        playbackSection.addRow(makeSettingRow(title: "顺序播放", trailing: sequentialSwitch))
        playbackSection.addRow(makeSettingRow(title: "随机播放", trailing: randomSwitch))
        let autoSwitchRow = makeSettingRow(title: "自动切换", trailing: autoSwitchSwitch)
        autoSwitchRowView = autoSwitchRow
        playbackSection.addRow(autoSwitchRow)

        intervalField.alignment = .right
        intervalField.translatesAutoresizingMaskIntoConstraints = false
        intervalField.delegate = self
        intervalField.widthAnchor.constraint(equalToConstant: 46).isActive = true

        timeUnitPopup.translatesAutoresizingMaskIntoConstraints = false
        for unit in TimeUnit.allCases {
            timeUnitPopup.addItem(withTitle: unit.rawValue)
            timeUnitPopup.lastItem?.representedObject = unit
        }

        let intervalControls = NSStackView(views: [intervalField, timeUnitPopup])
        intervalControls.orientation = .horizontal
        intervalControls.alignment = .centerY
        intervalControls.spacing = 8

        intervalRowView = makeSettingRow(title: "-  间隔时间", trailing: intervalControls)
        if let intervalRowView {
            playbackSection.addRow(intervalRowView)
        }

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        volumeValueLabel.alignment = .right
        volumeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        volumeValueLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let volumeControls = NSStackView(views: [volumeValueLabel, volumeSlider, muteSwitch])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 8
        playbackSection.addRow(makeSettingRow(title: "静音", trailing: volumeControls))

        // 播放速率行：开关控制滑块显隐，滑块宽度与音量条对齐。
        playbackRateSwitch.toolTip = "启用后可调整播放速率"
        playbackRateSlider.translatesAutoresizingMaskIntoConstraints = false
        playbackRateSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        playbackRateSlider.numberOfTickMarks = 12
        playbackRateSlider.allowsTickMarkValuesOnly = false
        playbackRateValueLabel.alignment = .right
        playbackRateValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        playbackRateValueLabel.translatesAutoresizingMaskIntoConstraints = false
        playbackRateValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let rateControls = NSStackView(views: [playbackRateValueLabel, playbackRateSlider, playbackRateSwitch])
        rateControls.orientation = .horizontal
        rateControls.alignment = .centerY
        rateControls.spacing = 8
        let rateRow = makeSettingRow(title: "播放速率", trailing: rateControls)
        playbackRateRowView = rateRow
        playbackSection.addRow(rateRow)
    }

    private func setupSystemSection() {
        // 系统集成区只放会影响全局快捷键、同步壁纸和开机行为的配置。
        startOnBootSwitch.toolTip = "开机时自动启动应用并恢复上次的壁纸设置"
        syncSystemWallpaperSwitch.toolTip = "每次切换壁纸时同步更新系统壁纸"
        systemHotkeysSwitch.toolTip = "允许使用全局 F1-F12 快捷键控制壁纸"

        systemSection.addRow(makeSettingRow(title: "开机自启动", trailing: startOnBootSwitch))
        systemSection.addRow(makeSettingRow(title: "同步系统壁纸", trailing: syncSystemWallpaperSwitch))
        systemSection.addRow(makeSettingRow(title: "响应系统快捷键", trailing: systemHotkeysSwitch))

        hotkeyRowsStack.orientation = .vertical
        hotkeyRowsStack.alignment = .leading
        hotkeyRowsStack.distribution = .gravityAreas
        hotkeyRowsStack.spacing = 0
        hotkeyRowsStack.translatesAutoresizingMaskIntoConstraints = false

        for action in SystemHotkeyAction.allCases {
            let toggle = NSSwitch()
            let popup = NSPopUpButton()

            let controls = NSStackView(views: [popup, toggle])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 8

            if !hotkeyRowsStack.arrangedSubviews.isEmpty {
                let separator = makeInlineSeparator(horizontalInset: 14)
                hotkeyRowsStack.addArrangedSubview(separator)
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.widthAnchor.constraint(equalTo: hotkeyRowsStack.widthAnchor).isActive = true
            }

            let row = makeSettingRow(title: action.displayName, trailing: controls)
            hotkeyRowsStack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: hotkeyRowsStack.widthAnchor).isActive = true

            hotkeyEnableSwitches[action] = toggle
            hotkeyPopups[action] = popup
        }

        hotkeyRowsContainer = makeEmbeddedRow(content: hotkeyRowsStack)
        if let hotkeyRowsContainer {
            systemSection.addRow(hotkeyRowsContainer)
        }
    }

    private func setupPerformanceSection() {
        // 性能区的开关会直接影响引擎暂停状态，改动后必须同步到 WallpaperEngine。
        pauseOtherAppFullscreenSwitch.toolTip = "当其他应用进入全屏并占据主要桌面空间时暂停壁纸播放"
        pauseWhenUnpluggedSwitch.toolTip = "使用电池时暂停壁纸播放以节省电量"
        pauseWhenIdleSwitch.toolTip = "当电脑长时间不活跃时暂停壁纸播放"

        performanceSection.addRow(makeSettingRow(title: "其他应用焦点时暂停", trailing: pauseOtherAppFocusedSwitch))
        performanceSection.addRow(makeSettingRow(title: "其他应用全屏时暂停", trailing: pauseOtherAppFullscreenSwitch))
        performanceSection.addRow(makeSettingRow(title: "未连接电源时暂停播放", trailing: pauseWhenUnpluggedSwitch))
        performanceSection.addRow(makeSettingRow(title: "电脑不活跃时暂停播放", trailing: pauseWhenIdleSwitch))

        for value in [5, 10, 15, 20, 30, 60] {
            idleTimeoutPopup.addItem(withTitle: "\(value)分钟")
            idleTimeoutPopup.lastItem?.representedObject = value
        }
        idleTimeoutRowView = makeSettingRow(title: "-  不活跃时间", trailing: idleTimeoutPopup)
        if let idleTimeoutRowView {
            performanceSection.addRow(idleTimeoutRowView)
        }
    }

    private func setupDisplaySection() {
        // 显示区只处理屏幕适配和画面比例，不混入播放策略。
        multiDisplaySwitch.toolTip = "在所有显示器上显示视频壁纸"
        displaySection.addRow(makeSettingRow(title: "多屏适配", trailing: multiDisplaySwitch))

        let fillModeControls = NSStackView(views: [fillModeFitButton, fillModeFillButton])
        fillModeControls.orientation = .horizontal
        fillModeControls.alignment = .centerY
        fillModeControls.spacing = 16
        displaySection.addRow(makeSettingRow(title: "视频填充模式", trailing: fillModeControls))
    }

    private func setupMaintenanceSection() {
        // 维护区只承载导入导出、清缓存和恢复默认这类高风险动作，和普通设置分开。
        // 导出/导入按钮去掉 bordered 样式，避免与 section 背景产生双层视觉叠加。
        exportProfileButton.isBordered = false
        exportProfileButton.bezelStyle = .rounded
        exportProfileButton.contentTintColor = .controlAccentColor
        exportProfileButton.isEnabled = true
        exportProfileButton.target = self
        exportProfileButton.action = #selector(handleExportProfile)
        importProfileButton.isBordered = false
        importProfileButton.bezelStyle = .rounded
        importProfileButton.contentTintColor = .controlAccentColor
        importProfileButton.isEnabled = true
        importProfileButton.target = self
        importProfileButton.action = #selector(handleImportProfile)

        clearCacheButton.isBordered = false

        resetSettingsButton.isBordered = false
        resetSettingsButton.contentTintColor = .systemRed

        let profileButtons = NSStackView(views: [exportProfileButton, importProfileButton])
        profileButtons.orientation = .horizontal
        profileButtons.alignment = .centerY
        profileButtons.spacing = 20
        profileSettingsSection.addRow(makeCenteredControlRow(content: profileButtons))
        clearCacheSection.addRow(makeCenteredControlRow(content: clearCacheButton))
        resetSettingsSection.addRow(makeCenteredControlRow(content: resetSettingsButton))
    }

    private func applyNativeControlSizes() {
        // 控件尺寸统一收口，避免每个控件自己定义大小导致页面观感失衡。
        let switches: [NSSwitch] = [
            loopSwitch,
            randomSwitch,
            sequentialSwitch,
            autoSwitchSwitch,
            muteSwitch,
            playbackRateSwitch,
            startOnBootSwitch,
            syncSystemWallpaperSwitch,
            systemHotkeysSwitch,
            pauseOtherAppFocusedSwitch,
            pauseOtherAppFullscreenSwitch,
            pauseWhenUnpluggedSwitch,
            pauseWhenIdleSwitch,
            multiDisplaySwitch
        ]
        switches.forEach { $0.controlSize = .mini }
        hotkeyEnableSwitches.values.forEach { $0.controlSize = .mini }

        let popups: [NSPopUpButton] = [timeUnitPopup, idleTimeoutPopup] + hotkeyPopups.values
        popups.forEach { $0.controlSize = .small }

        intervalField.controlSize = .small
        volumeSlider.controlSize = .regular
        playbackRateSlider.controlSize = .regular
        exportProfileButton.controlSize = .regular
        importProfileButton.controlSize = .regular
        clearCacheButton.controlSize = .regular
        resetSettingsButton.controlSize = .regular

        // 这四个按钮字号和字重单独强化，避免被系统 controlSize 默认字体压得偏小。
        let maintenanceFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        exportProfileButton.font = maintenanceFont
        importProfileButton.font = maintenanceFont
        clearCacheButton.font = maintenanceFont
        resetSettingsButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    }

    private func bindEvents() {
        // 所有 target/action 在这里集中绑定，避免控件在别处被悄悄改动后难以排查。
        loopSwitch.target = self
        loopSwitch.action = #selector(handleLoopToggle)
        randomSwitch.target = self
        randomSwitch.action = #selector(handleRandomToggle)
        sequentialSwitch.target = self
        sequentialSwitch.action = #selector(handleSequentialToggle)
        autoSwitchSwitch.target = self
        autoSwitchSwitch.action = #selector(handleAutoSwitchToggle)
        timeUnitPopup.target = self
        timeUnitPopup.action = #selector(handleTimeUnitChange)
        volumeSlider.target = self
        volumeSlider.action = #selector(handleVolumeChange)
        muteSwitch.target = self
        muteSwitch.action = #selector(handleMuteToggle)

        playbackRateSlider.target = self
        playbackRateSlider.action = #selector(handlePlaybackRateChange)
        playbackRateSwitch.target = self
        playbackRateSwitch.action = #selector(handlePlaybackRateSwitchToggle)

        startOnBootSwitch.target = self
        startOnBootSwitch.action = #selector(handleStartOnBootToggle)
        syncSystemWallpaperSwitch.target = self
        syncSystemWallpaperSwitch.action = #selector(handleSyncSystemWallpaperToggle)
        systemHotkeysSwitch.target = self
        systemHotkeysSwitch.action = #selector(handleSystemHotkeysToggle)

        for action in SystemHotkeyAction.allCases {
            hotkeyEnableSwitches[action]?.target = self
            hotkeyEnableSwitches[action]?.action = #selector(handleHotkeyEnableToggle(_:))
            hotkeyEnableSwitches[action]?.tag = hotkeyTag(for: action)

            hotkeyPopups[action]?.target = self
            hotkeyPopups[action]?.action = #selector(handleHotkeyPopupChange(_:))
            hotkeyPopups[action]?.tag = hotkeyTag(for: action)
        }

        pauseOtherAppFocusedSwitch.target = self
        pauseOtherAppFocusedSwitch.action = #selector(handlePerformanceToggle)
        pauseOtherAppFullscreenSwitch.target = self
        pauseOtherAppFullscreenSwitch.action = #selector(handlePerformanceToggle)
        pauseWhenUnpluggedSwitch.target = self
        pauseWhenUnpluggedSwitch.action = #selector(handlePerformanceToggle)
        pauseWhenIdleSwitch.target = self
        pauseWhenIdleSwitch.action = #selector(handlePerformanceToggle)
        idleTimeoutPopup.target = self
        idleTimeoutPopup.action = #selector(handleIdleTimeoutChange)

        multiDisplaySwitch.target = self
        multiDisplaySwitch.action = #selector(handleMultiDisplayToggle)
        fillModeFitButton.target = self
        fillModeFitButton.action = #selector(handleFillModeChange(_:))
        fillModeFillButton.target = self
        fillModeFillButton.action = #selector(handleFillModeChange(_:))

        clearCacheButton.target = self
        clearCacheButton.action = #selector(handleClearCache)
        exportProfileButton.target = self
        exportProfileButton.action = #selector(handleExportProfile)
        importProfileButton.target = self
        importProfileButton.action = #selector(handleImportProfile)
        resetSettingsButton.target = self
        resetSettingsButton.action = #selector(handleResetSettings)
    }

    private func observeManager() {
        // 设置页只订阅 manager 的最终快照，不自己维护派生状态。
        wallpaperManager.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromState()
            }
            .store(in: &cancellables)
    }

    private func makeSettingRow(title: String, subtitle: String? = nil, trailing: NSView, leadingInset: CGFloat = 0) -> NSView {
        // 标题在左、控件在右，中间留伸缩空白，保持系统设置类页面的稳定对齐。
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let leadingView: NSView
        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.textColor = .secondaryLabelColor
            let textStack = NSStackView(views: [titleLabel, subtitleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.distribution = .gravityAreas
            textStack.spacing = 2
            leadingView = textStack
        } else {
            leadingView = titleLabel
        }

        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowStack = NSStackView(views: [leadingView, spacer, trailing])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rowStack)
        let topInset: CGFloat = 8
        let bottomInset: CGFloat = 8
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14 + leadingInset),
            rowStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            rowStack.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
            rowStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomInset)
        ])
        return container
    }

    private func makeEmbeddedRow(content: NSView, centered: Bool = false) -> NSView {
        // 嵌入式行只包裹二级控件，不再重复加装饰容器，避免视觉层级失真。
        let row: NSStackView
        if centered {
            row = NSStackView(views: [NSView(), content, NSView()])
        } else {
            row = NSStackView(views: [content])
            content.translatesAutoresizingMaskIntoConstraints = false
            content.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }

        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return row
    }

    private func makeCenteredControlRow(content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func makeInlineSeparator(horizontalInset: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = AdaptiveSeparatorLineView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    @objc private func handleLoopToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setLoopPlaybackEnabled(loopSwitch.state == .on)
    }

    @objc private func handleRandomToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setRandomPlaybackEnabled(randomSwitch.state == .on)
    }

    @objc private func handleSequentialToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setSequentialPlaybackEnabled(sequentialSwitch.state == .on)
    }

    @objc private func handleAutoSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = autoSwitchSwitch.state == .on
        wallpaperManager.settings.autoSwitchEnabled = enabled
        if enabled {
            // 开启：从 0 重建 timer，通知引擎当前视频切换为循环模式（等 timer 到期再切换）。
            wallpaperManager.startAutoSwitchTimer()
            WallpaperEngine.shared.setLoopCurrentItem(true)
        } else {
            // 关闭：销毁 timer，通知引擎停止循环当前视频，视频播完后自然切下一张。
            wallpaperManager.stopAutoSwitchTimer()
            WallpaperEngine.shared.setLoopCurrentItem(false)
        }
    }

    @objc private func handleTimeUnitChange() {
        guard !isUpdatingUI else { return }
        guard let unit = timeUnitPopup.selectedItem?.representedObject as? TimeUnit else { return }
        wallpaperManager.settings.timeUnit = unit
        wallpaperManager.refreshAutoSwitchTimerIfNeeded()
    }

    @objc private func handleVolumeChange() {
        guard !isUpdatingUI else { return }
        let clampedVolume = Int(max(0, min(100, round(volumeSlider.doubleValue))))
        volumeValueLabel.stringValue = "\(clampedVolume)%"
        wallpaperManager.updateVolume(Double(clampedVolume))
    }

    @objc private func handleMuteToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.setMuted(muteSwitch.state == .on)
    }

    @objc private func handlePlaybackRateChange() {
        guard !isUpdatingUI else { return }
        // 滑块步长 0.25，上限 3.0。
        let snapped = (playbackRateSlider.doubleValue * 4).rounded() / 4
        let clamped = max(0.25, min(2.0, snapped))
        playbackRateValueLabel.stringValue = String(format: "%.2gx", clamped)
        wallpaperManager.settings.playbackRate = clamped
        wallpaperManager.applyPlaybackRateToEngine()
    }

    @objc private func handlePlaybackRateSwitchToggle() {
        guard !isUpdatingUI else { return }
        let enabled = playbackRateSwitch.state == .on
        wallpaperManager.settings.playbackRateEnabled = enabled
        playbackRateSlider.isHidden = !enabled
        playbackRateValueLabel.isHidden = !enabled
        // 关闭时把速率重置为正常速度，避免关掉开关后引擎还在以异常速率播放。
        if !enabled {
            wallpaperManager.settings.playbackRate = 1.0
        }
    }

    @objc private func handleStartOnBootToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.startOnBoot = (startOnBootSwitch.state == .on)
        wallpaperManager.updateLoginItemStatus()
    }

    @objc private func handleSyncSystemWallpaperToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.syncSystemWallpaper = (syncSystemWallpaperSwitch.state == .on)
    }

    @objc private func handleSystemHotkeysToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.systemHotkeysEnabled = (systemHotkeysSwitch.state == .on)
    }

    @objc private func handleHotkeyEnableToggle(_ sender: NSSwitch) {
        guard !isUpdatingUI else { return }
        guard let action = hotkeyAction(from: sender.tag) else { return }

        if sender.state == .on {
            if assignedShortcut(for: action) == .none {
                let available = firstAvailableShortcut(for: action)
                if available != .none {
                    setAssignedShortcut(available, for: action)
                }
            }
        } else {
            setAssignedShortcut(.none, for: action)
        }
        refreshFromState()
    }

    @objc private func handleHotkeyPopupChange(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let action = hotkeyAction(from: sender.tag) else { return }
        guard let shortcut = sender.selectedItem?.representedObject as? FunctionKeyShortcut else { return }
        if isShortcutAvailable(shortcut, for: action) {
            setAssignedShortcut(shortcut, for: action)
        }
        refreshFromState()
    }

    @objc private func handlePerformanceToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.pauseWhenOtherAppFocused = (pauseOtherAppFocusedSwitch.state == .on)
        wallpaperManager.settings.pauseWhenOtherAppFullscreen = (pauseOtherAppFullscreenSwitch.state == .on)
        wallpaperManager.settings.pauseWhenUnplugged = (pauseWhenUnpluggedSwitch.state == .on)
        wallpaperManager.settings.pauseWhenIdle = (pauseWhenIdleSwitch.state == .on)
        wallpaperManager.applyEngineSettings()
    }

    @objc private func handleIdleTimeoutChange() {
        guard !isUpdatingUI else { return }
        guard let value = idleTimeoutPopup.selectedItem?.representedObject as? Int else { return }
        wallpaperManager.settings.idleTimeoutMinutes = value
        wallpaperManager.applyEngineSettings()
    }

    @objc private func handleMultiDisplayToggle() {
        guard !isUpdatingUI else { return }
        wallpaperManager.settings.multiDisplayEnabled = (multiDisplaySwitch.state == .on)
        wallpaperManager.applyEngineSettings(reloadWallpaper: true)
    }

    @objc private func handleFillModeChange(_ sender: NSButton) {
        guard !isUpdatingUI else { return }
        let mode: VideoFillMode = (sender == fillModeFitButton) ? .aspectFit : .aspectFill
        selectFillMode(mode)
        wallpaperManager.settings.videoFillMode = mode
        // 填充模式只需通知引擎更新 gravity + 播放动画，不重建播放链路。
        WallpaperEngine.shared.setFillMode(mode.ipcValue)
    }

    @objc private func handleClearCache() {
        let alert = makeAppAlert(
            title: "清空缓存",
            message: "将删除视频库的所有缩略图和静帧缓存，不会删除已导入的视频/图片和当前设置。图片库无独立缓存。",
            buttons: ["清空", "取消"]
        )
        presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.wallpaperManager.clearAllCaches()
            let result = makeAppAlert(
                title: "缓存已清空",
                message: "下次浏览或切换壁纸时会重新生成缓存。"
            )
            presentAppAlert(result, in: appModalHostWindow())
        }
    }

    @objc private func handleExportProfile() {
        let panel = NSSavePanel()
        panel.title = "导出个人设置"
        panel.nameFieldStringValue = "MyWallpaperX-Profile.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false

        presentSavePanel(panel) { [weak self] targetURL in
            guard let self, let targetURL else { return }
            do {
                let summary = try self.wallpaperManager.exportPersonalSettings(to: targetURL)
                let done = makeAppAlert(
                    title: "导出完成",
                    message: "已导出 \(summary.wallpaperCount) 条壁纸配置，\(summary.tagCount) 个标签。"
                )
                presentAppAlert(done, in: self.preferredHostWindow())
            } catch {
                let failed = makeAppAlert(
                    title: "导出失败",
                    message: error.localizedDescription
                )
                presentAppAlert(failed, in: self.preferredHostWindow())
            }
        }
    }

    @objc private func handleImportProfile() {
        let panel = NSOpenPanel()
        panel.title = "导入个人设置"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        presentOpenPanel(panel) { [weak self] sourceURL in
            guard let self, let sourceURL else { return }
            let hostWindow = self.preferredHostWindow()
            let confirm = makeAppAlert(
                title: "导入个人设置",
                message: "将恢复设置项、标签和收藏信息；同路径项目会覆盖为导入配置，缺失文件会保留并提示检查路径。",
                buttons: ["导入", "取消"]
            )
            presentAppAlert(confirm, in: hostWindow) { [weak self] confirmResponse in
                guard let self, confirmResponse == .alertFirstButtonReturn else { return }
                do {
                    let summary = try self.wallpaperManager.importPersonalSettings(from: sourceURL)
                    let done = makeAppAlert(
                        title: "导入完成",
                        message: """
                        更新项目：\(summary.mergedWallpaperCount) 个
                        新增项目：\(summary.createdWallpaperCount) 个
                        标签总数：\(summary.tagCount) 个
                        缺失路径：\(summary.missingPathCount) 个
                        """
                    )
                    presentAppAlert(done, in: hostWindow)
                } catch {
                    let failed = makeAppAlert(
                        title: "导入失败",
                        message: error.localizedDescription
                    )
                    presentAppAlert(failed, in: hostWindow)
                }
            }
        }
    }

    private func preferredHostWindow() -> NSWindow? {
        window ?? appModalHostWindow()
    }

    private func presentSavePanel(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        // 优先 sheet，只有窗口不在前台时才回退到 modal，减少导入导出对主界面的打断。
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            let hostWindow = self.preferredHostWindow()
            NSApp.activate(ignoringOtherApps: true)

            if let hostWindow, hostWindow.isVisible {
                panel.beginSheetModal(for: hostWindow) { response in
                    completion(response == .OK ? panel.url : nil)
                }
                return
            }

            let response = panel.runModal()
            completion(response == .OK ? panel.url : nil)
        }
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
        // 导入面板与导出面板共用同一展示策略，保证行为和系统面板一致。
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            let hostWindow = self.preferredHostWindow()
            NSApp.activate(ignoringOtherApps: true)

            if let hostWindow, hostWindow.isVisible {
                panel.beginSheetModal(for: hostWindow) { response in
                    completion(response == .OK ? panel.url : nil)
                }
                return
            }

            let response = panel.runModal()
            completion(response == .OK ? panel.urls.first : nil)
        }
    }

    @objc private func handleResetSettings() {
        let alert = makeAppAlert(
            title: "重置设置",
            message: "将清空视频库和图片库的所有壁纸、标签和最近使用，并恢复所有设置为初次安装状态。此操作不可撤销，确定要继续吗？",
            buttons: ["确定", "取消"]
        )
        presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.wallpaperManager.resetToFreshInstallState()
        }
    }

    private func assignedShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        // 快捷键状态源只读写 settings，popup 不直接保存自己的状态。
        switch action {
        case .previous:
            return wallpaperManager.settings.previousWallpaperHotkey
        case .next:
            return wallpaperManager.settings.nextWallpaperHotkey
        case .playPause:
            return wallpaperManager.settings.togglePlaybackHotkey
        case .muteToggle:
            return wallpaperManager.settings.toggleMuteHotkey
        }
    }

    private func setAssignedShortcut(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) {
        // 统一通过 settings 写回，避免每个热键 row 各自维护一份绑定结果。
        switch action {
        case .previous:
            wallpaperManager.settings.previousWallpaperHotkey = shortcut
        case .next:
            wallpaperManager.settings.nextWallpaperHotkey = shortcut
        case .playPause:
            wallpaperManager.settings.togglePlaybackHotkey = shortcut
        case .muteToggle:
            wallpaperManager.settings.toggleMuteHotkey = shortcut
        }
    }

    private func usedShortcuts(excluding action: SystemHotkeyAction) -> Set<FunctionKeyShortcut> {
        Set(
            SystemHotkeyAction.allCases
                .filter { $0 != action }
                .map { assignedShortcut(for: $0) }
                .filter { $0 != .none }
        )
    }

    private func isShortcutAvailable(_ shortcut: FunctionKeyShortcut, for action: SystemHotkeyAction) -> Bool {
        shortcut == .none || shortcut == assignedShortcut(for: action) || !usedShortcuts(excluding: action).contains(shortcut)
    }

    private func firstAvailableShortcut(for action: SystemHotkeyAction) -> FunctionKeyShortcut {
        FunctionKeyShortcut.allCases.first(where: { $0 != .none && isShortcutAvailable($0, for: action) }) ?? .none
    }

    private func refreshHotkeyRows() {
        // 热键行刷新时同时处理启用开关和下拉可用性，保持“一个动作一行”一致。
        let masterEnabled = wallpaperManager.settings.systemHotkeysEnabled
        for action in SystemHotkeyAction.allCases {
            guard let toggle = hotkeyEnableSwitches[action],
                  let popup = hotkeyPopups[action] else {
                continue
            }
            let shortcut = assignedShortcut(for: action)
            let enabled = shortcut != .none
            toggle.state = enabled ? .on : .off
            popup.isEnabled = masterEnabled && enabled
            reloadHotkeyPopup(popup, for: action, selected: shortcut)
        }
    }

    private func reloadHotkeyPopup(_ popup: NSPopUpButton, for action: SystemHotkeyAction, selected: FunctionKeyShortcut) {
        // 这里要重新构建整份菜单，因为禁用项和当前选项会随其它快捷键变化而变化。
        popup.removeAllItems()
        for shortcut in FunctionKeyShortcut.allCases {
            popup.addItem(withTitle: shortcut.displayName)
            popup.lastItem?.representedObject = shortcut
            popup.lastItem?.isEnabled = isShortcutAvailable(shortcut, for: action)
        }
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? FunctionKeyShortcut) == selected }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func selectTimeUnit(_ unit: TimeUnit) {
        if let index = timeUnitPopup.itemArray.firstIndex(where: { ($0.representedObject as? TimeUnit) == unit }) {
            timeUnitPopup.selectItem(at: index)
        }
    }

    private func selectIdleTimeout(_ minutes: Int) {
        if let index = idleTimeoutPopup.itemArray.firstIndex(where: { ($0.representedObject as? Int) == minutes }) {
            idleTimeoutPopup.selectItem(at: index)
        } else {
            idleTimeoutPopup.selectItem(at: 0)
        }
    }

    private func selectFillMode(_ mode: VideoFillMode) {
        fillModeFitButton.state = (mode == .aspectFit) ? .on : .off
        fillModeFillButton.state = (mode == .aspectFill) ? .on : .off
    }

    private func hotkeyTag(for action: SystemHotkeyAction) -> Int {
        switch action {
        case .previous: return 1
        case .next: return 2
        case .playPause: return 3
        case .muteToggle: return 4
        }
    }

    private func hotkeyAction(from tag: Int) -> SystemHotkeyAction? {
        switch tag {
        case 1: return .previous
        case 2: return .next
        case 3: return .playPause
        case 4: return .muteToggle
        default: return nil
        }
    }
}

extension AppKitSettingsContainerView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        // 间隔输入框只在结束编辑时写回，避免每个按键都触发计时器重建。
        guard !isUpdatingUI else { return }
        guard let textField = notification.object as? NSTextField, textField == intervalField else { return }
        let parsed = Int(textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? wallpaperManager.settings.randomInterval
        wallpaperManager.settings.randomInterval = max(1, parsed)
        wallpaperManager.refreshAutoSwitchTimerIfNeeded()
    }
}
