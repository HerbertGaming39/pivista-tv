import QtQuick

Item {
    id: settings

    property string page: ""
    property var pending: ({})
    property string notice: ""
    property bool noticeIsError: false

    property var net: ({})
    property var netTest: ({})
    property var wifi: []
    property var audio: ({})
    property var display: ({})
    property var sysInfo: ({})
    property var sysStatus: ({})
    property var update: ({})
    property var updateCheck: ({})
    property var appUpdate: ({"installed": "", "available": false, "job": {"state": "idle"}})
    property var android: ({})
    property bool showLogs: false
    property string logsText: ""
    property string wifiSsid: ""
    property bool wifiSecure: true
    property var pendingConfirm: null

    signal requestHeaderFocus()

    readonly property var sections: [
        { id: "network", title: "Network", subtitle: "Wi-Fi, Ethernet and connectivity" },
        { id: "display", title: "Display", subtitle: "Resolution, interface size and idle screen" },
        { id: "appearance", title: "Appearance", subtitle: "Theme, wallpaper, home rows and clock" },
        { id: "audio", title: "Audio", subtitle: "HDMI output, volume and speaker test" },
        { id: "applications", title: "Applications", subtitle: "Favourites, hidden apps and web shortcuts" },
        { id: "system", title: "System", subtitle: "Build, temperature, storage and diagnostics" },
        { id: "updates", title: "Updates", subtitle: "Check for and install system updates" },
        { id: "privacy", title: "Privacy and security", subtitle: "Browser data, telemetry and Android status" },
        { id: "about", title: "About", subtitle: "Version, licences and build provenance" }
    ]

    function api(action, params, onOk, timeout, onErr) {
        const id = control.call(action, params, timeout === undefined ? 30000 : timeout)
        pending[id] = { ok: onOk, err: onErr }
    }

    function flash(message, isError) {
        notice = message
        noticeIsError = isError === true
        noticeTimer.restart()
    }

    function fmtBytes(bytes) {
        if (!bytes) return "0 B"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let value = bytes
        let unit = 0
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
        return value.toFixed(value >= 10 ? 0 : 1) + " " + units[unit]
    }

    function fmtUptime(seconds) {
        const total = seconds || 0
        const days = Math.floor(total / 86400)
        const hours = Math.floor((total % 86400) / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        if (days > 0) return days + " d " + hours + " h"
        if (hours > 0) return hours + " h " + minutes + " min"
        return minutes + " min"
    }

    function loadNetwork() {
        api("network.status", {}, function (data) { net = data })
        api("network.connectivity", {}, function (data) { netTest = data }, 20000)
    }

    function testConnectivity() {
        flash("Testing internet connection…", false)
        api("network.connectivity", {}, function (data) {
            netTest = data
            if (data.online)
                flash("Internet reachable · DNS OK", false)
            else if (data.dns)
                flash("DNS works, but NetworkManager reports " + (data.nm || "unknown"), true)
            else
                flash("No internet access. Check Wi-Fi/Ethernet and DNS.", true)
        }, 20000, function (message) {
            flash(message, true)
        })
    }

    function scanWifi() {
        flash("Scanning for Wi-Fi networks…", false)
        api("network.scan", { rescan: true }, function (data) {
            wifi = data.networks || []
            flash(wifi.length + " networks found", false)
            if (wifi.length > 0)
                wifiActions.focusFirst()
        }, 60000, function (message) { flash(message, true) })
    }

    function beginConnect(ssid, secure) {
        wifiSsid = ssid
        wifiSecure = secure
        if (secure) {
            wifiDialog.hint = "Enter the password for " + ssid + ". The password is sent only to NetworkManager."
            wifiDialog.open()
        } else {
            connectWifi("")
        }
    }

    function connectWifi(password) {
        flash("Connecting to " + wifiSsid + "…", false)
        api("network.connect", { ssid: wifiSsid, password: password }, function (data) {
            if (wifiDialog.visible) wifiDialog.close()
            flash("Connected to " + wifiSsid, false)
            loadNetwork()
            wifiActions.focusFirst()
        }, 90000, function (message) {
            if (wifiDialog.visible) wifiDialog.fail(message)
            else flash(message, true)
        })
    }

    function loadDisplay() {
        api("display.status", {}, function (data) { display = data })
    }

    function loadAudio() {
        api("audio.status", {}, function (data) { audio = data })
    }

    function loadSystem() {
        api("system.info", {}, function (data) { sysInfo = data })
        api("system.status", {}, function (data) { sysStatus = data })
    }

    function loadUpdate() {
        api("update.status", {}, function (data) { update = data })
    }

    function loadAppUpdate() {
        api("app.update.status", {}, function (data) { appUpdate = data })
    }

    function checkAppUpdate() {
        flash("Checking GitHub for a signed PiVista release…", false)
        api("app.update.check", { allow_prerelease: AppSettings.appPrerelease }, function (data) {
            appUpdate = data
            if (data.available)
                flash("PiVista " + data.latest + " is available", false)
            else if (data.reason)
                flash(data.reason, true)
            else
                flash("PiVista " + data.installed + " is up to date", false)
        }, 60000, function (message) { flash(message, true) })
    }

    function downloadAppUpdate() {
        api("app.update.download", {
            confirm: true,
            version: appUpdate.latest,
            allow_prerelease: AppSettings.appPrerelease
        }, function () {
            flash("Downloading PiVista " + appUpdate.latest + "…", false)
            loadAppUpdate()
        }, 30000, function (message) { flash(message, true); loadAppUpdate() })
    }

    function installAppUpdate() {
        askConfirm("Install PiVista " + appUpdate.latest,
            "The signed launcher will replace the current one. Settings, favourites, apps and network configuration are preserved. Playback is not interrupted now; restart the launcher when you are ready.",
            "Install", false, function () {
                api("app.update.install", { confirm: true }, function () {
                    flash("Installing launcher update…", false)
                    loadAppUpdate()
                }, 30000, function (message) { flash(message, true); loadAppUpdate() })
            })
    }

    function postponeAppUpdate() {
        api("app.update.postpone", { version: appUpdate.latest }, function (data) {
            appUpdate = data
            flash("Update postponed", false)
        }, 15000, function (message) { flash(message, true) })
    }

    function rollbackAppUpdate() {
        askConfirm("Roll back launcher",
            "Restore the launcher that was installed before the last update. User settings and app data are not changed. The launcher must restart afterwards.",
            "Roll back", true, function () {
                api("app.update.rollback", { confirm: true }, function (data) {
                    appUpdate = data
                    flash("Previous launcher restored; restart to use it", false)
                }, 30000, function (message) { flash(message, true); loadAppUpdate() })
            })
    }

    function restartLauncher() {
        askConfirm("Restart launcher",
            "The launcher will restart now. Any video or application opened from PiVista TV will be closed.",
            "Restart now", true, function () {
                api("app.update.restart", { confirm: true }, function () {
                    flash("Restarting the launcher…", false)
                }, 15000, function (message) { flash(message, true) })
            })
    }

    function appUpdateActionItems() {
        const job = appUpdate.job || ({})
        const state = job.state || "idle"
        const list = [{ id: "check", label: "Check for launcher updates", detail: "official GitHub release" }]
        if (appUpdate.available) {
            if (state === "downloaded" || state === "installed")
                list.push({ id: "install", label: "Install PiVista " + appUpdate.latest, detail: "signed and reversible" })
            else if (state === "downloading")
                list.push({ id: "download", label: "Downloading… " + (job.progress || 0) + "%", detail: fmtBytes(job.downloaded) + " of " + fmtBytes(appUpdate.size) })
            else
                list.push({ id: "download", label: "Download PiVista " + appUpdate.latest, detail: fmtBytes(appUpdate.size) })
            list.push({ id: "postpone", label: "Postpone this update", detail: "remind me later" })
        }
        if (job.restart_required === true)
            list.push({ id: "restart", label: "Restart launcher to finish", detail: "closes running apps" })
        if (appUpdate.rollback_available)
            list.push({ id: "rollback", label: "Roll back to previous launcher", detail: appUpdate.rollback_version || "last good version" })
        list.push({
            id: "prerelease",
            label: (AppSettings.appPrerelease ? "Disable" : "Allow") + " prerelease updates",
            detail: AppSettings.appPrerelease ? "enabled" : "stable only"
        })
        list.push({ id: "packages_check", label: "Check system packages", detail: "Debian apt" })
        list.push({ id: "packages_install", label: "Install system packages", detail: "reboot may be required" })
        list.push({ id: "log", label: showLogs ? "Hide update log" : "Show update log", detail: "" })
        return list
    }

    function handleAppUpdateAction(index) {
        const item = appUpdateActionItems()[index]
        if (!item) return
        if (item.id === "check") {
            checkAppUpdate()
        } else if (item.id === "download") {
            downloadAppUpdate()
        } else if (item.id === "install") {
            installAppUpdate()
        } else if (item.id === "postpone") {
            postponeAppUpdate()
        } else if (item.id === "restart") {
            restartLauncher()
        } else if (item.id === "rollback") {
            rollbackAppUpdate()
        } else if (item.id === "prerelease") {
            AppSettings.appPrerelease = !AppSettings.appPrerelease
            flash(AppSettings.appPrerelease ? "Prerelease updates enabled" : "Only stable releases will be offered", false)
            appUpdate = ({"installed": appUpdate.installed, "available": false, "job": {"state": "idle"}})
        } else if (item.id === "packages_check") {
            flash("Checking Debian package updates…", false)
            api("update.check", {}, function (data) {
                updateCheck = data
                flash(data.available + " package updates available", false)
            }, 240000, function (message) { flash(message, true) })
        } else if (item.id === "packages_install") {
            askConfirm("Install system packages",
                "Debian package updates do not have automatic A/B rollback. Do not power off. The launcher update above is separate and keeps its own rollback copy.",
                "Install", true, function () {
                    api("update.apply", { confirm: true }, function () {
                        flash("System package update started", false)
                        loadUpdate()
                    }, 30000, function (message) { flash(message, true) })
                })
        } else if (item.id === "log") {
            showLogs = !showLogs
            loadUpdateHistory()
        }
    }

    function loadAndroid() {
        api("android.status", {}, function (data) { android = data })
    }

    function loadPage() {
        if (page === "network") loadNetwork()
        else if (page === "display") loadDisplay()
        else if (page === "audio") loadAudio()
        else if (page === "system") loadSystem()
        else if (page === "updates") { loadUpdate(); loadAppUpdate(); loadUpdateHistory() }
        else if (page === "privacy") { loadAndroid() }
        else if (page === "about") { loadSystem(); loadAppUpdate() }
    }

    function openPage(id) {
        page = id
        showLogs = false
        Qt.callLater(focusPage)
    }

    function closePage() {
        page = ""
        Qt.callLater(function () { sectionsList.forceActiveFocus() })
    }

    function focusPage() {
        let focused = false
        if (page === "network") focused = netActions.focusFirst()
        else if (page === "display") focused = displayModes.focusFirst()
        else if (page === "appearance") focused = themeActions.focusFirst()
        else if (page === "audio") focused = audioActions.focusFirst()
        else if (page === "applications") focused = appActions.focusFirst()
        else if (page === "system") focused = systemActions.focusFirst()
        else if (page === "updates") focused = updateActions.focusFirst()
        else if (page === "privacy") focused = privacyActions.focusFirst()
        else if (page === "about") focused = aboutActions.focusFirst()
        // Some pages have no actionable rows until hardware reports a mode or
        // sink. Keep Back/Escape usable instead of leaving focus nowhere.
        if (!focused)
            settings.forceActiveFocus()
    }

    function focusContent() {
        if (page === "") {
            sectionsList.currentIndex = 0
            sectionsList.forceActiveFocus()
        } else {
            focusPage()
        }
    }

    function askConfirm(title, message, label, danger, callback) {
        pendingConfirm = callback
        confirmDialog.title = title
        confirmDialog.message = message
        confirmDialog.confirmLabel = label
        confirmDialog.danger = danger
        confirmDialog.open()
    }

    function loadUpdateHistory() {
        api("update.history", {}, function (data) { logsText = data.log_tail || "" })
    }

    function formatLogTail(text) {
        const lines = (text || "").split("\n")
        return lines.slice(Math.max(0, lines.length - 18)).join("\n")
    }

    Component.onCompleted: {
        if (initialSettingsPage.length > 0)
            openPage(initialSettingsPage)
        else
            loadUpdate()
    }

    Connections {
        target: control
        function onResponse(id, data) {
            const handler = settings.pending[id]
            if (handler) {
                delete settings.pending[id]
                if (handler.ok) handler.ok(data)
            }
        }
        function onFailed(id, code, message) {
            const handler = settings.pending[id]
            if (handler) {
                delete settings.pending[id]
                if (handler.err) handler.err(message)
                else settings.flash(message, true)
            }
        }
    }

    Timer {
        id: noticeTimer
        interval: 6000
        onTriggered: settings.notice = ""
    }

    Timer {
        interval: 2500
        repeat: true
        running: settings.update && settings.update.state === "running"
        onTriggered: settings.loadUpdate()
    }

    Timer {
        interval: 1000
        repeat: true
        running: settings.appUpdate.job && (settings.appUpdate.job.state === "downloading" || settings.appUpdate.job.state === "installing")
        onTriggered: settings.loadAppUpdate()
    }

    // ---------------------------------------------------------------- root
    ListView {
        id: sectionsList
        anchors.fill: parent
        visible: settings.page === ""
        model: settings.sections
        spacing: Theme.s(8)
        clip: true
        focus: true
        keyNavigationWraps: false

        Keys.onReturnPressed: if (currentItem) settings.openPage(model[currentIndex].id)
        Keys.onEnterPressed: if (currentItem) settings.openPage(model[currentIndex].id)
        Keys.onUpPressed: {
            if (currentIndex === 0) settings.requestHeaderFocus()
            else currentIndex--
        }
        Keys.onEscapePressed: settings.requestHeaderFocus()

        delegate: Rectangle {
            width: sectionsList.width
            height: Theme.s(78)
            radius: Theme.s(14)
            color: ListView.isCurrentItem ? Theme.surfaceHigh : Theme.surface
            border.width: ListView.isCurrentItem ? Theme.s(2) : Theme.s(1)
            border.color: ListView.isCurrentItem ? Theme.accent : Qt.rgba(1, 1, 1, 0.06)

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.s(22)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Theme.s(90)
                spacing: Theme.s(2)

                Text {
                    text: modelData.title
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(19)
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: modelData.subtitle
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(13)
                    elide: Text.ElideRight
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(22)
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: ListView.isCurrentItem ? Theme.accent : Theme.textFaint
                font.pixelSize: Theme.s(24)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    sectionsList.currentIndex = index
                    settings.openPage(modelData.id)
                }
            }
        }
    }

    // ------------------------------------------------------------- network
    Item {
        id: networkPage
        anchors.fill: parent
        visible: settings.page === "network"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "Network"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            InfoLine { width: parent.width; label: "Connection"; value: settings.net.connection ? settings.net.connection : "not connected" }
            InfoLine { width: parent.width; label: "Address"; value: settings.net.ip ? settings.net.ip : "—" }
            InfoLine { width: parent.width; label: "Internet"; value: settings.netTest.online ? "reachable" : (settings.netTest.nm ? settings.netTest.nm : "not tested") }

            ActionList {
                id: netActions
                width: parent.width
                actions: [
                    { label: "Scan for Wi-Fi networks", detail: "find nearby networks" },
                    { label: settings.net.wifi_connected ? "Disconnect Wi-Fi" : "Wi-Fi not connected", detail: settings.net.wifi_connected ? settings.net.connection : "connect first" },
                    { label: "Test internet connection", detail: "DNS and NetworkManager" },
                    { label: "Refresh status", detail: "" }
                ]
                onTriggered: function (index) {
                    if (index === 0) {
                        settings.scanWifi()
                    } else if (index === 1) {
                        if (!settings.net.wifi_connected) {
                            settings.flash("Wi-Fi is not connected.", true)
                            return
                        }
                        const wifi = (settings.net.devices || []).find(function (device) {
                            return device.type === "wifi" && device.state === "connected"
                        })
                        if (!wifi) {
                            settings.flash("No connected Wi-Fi device.", true)
                            return
                        }
                        settings.api("network.disconnect", { device: wifi.device }, function () {
                            settings.flash("Wi-Fi disconnected", false)
                            settings.loadNetwork()
                        }, 30000, function (m) { settings.flash(m, true) })
                    } else if (index === 2) {
                        settings.testConnectivity()
                    } else {
                        settings.loadNetwork()
                    }
                }
                onNavigateDown: if (wifiActions.actions.length > 0) wifiActions.focusFirst()
            }

            Text {
                text: "Wi-Fi networks"
                visible: settings.wifi.length > 0
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(15)
                font.weight: Font.DemiBold
            }

            ActionList {
                id: wifiActions
                width: parent.width
                height: Math.min(Theme.s(300), implicitHeight)
                actions: settings.wifi.map(function (network) {
                    return {
                        label: network.ssid,
                        detail: (network.secure ? "locked" : "open") + " · " + network.signal + "%"
                    }
                })
                onTriggered: function (index) {
                    const network = settings.wifi[index]
                    if (network) settings.beginConnect(network.ssid, network.secure)
                }
                onNavigateUp: netActions.focusFirst()
            }

            Text {
                text: "Back returns to Settings"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
            }
        }
    }

    // ------------------------------------------------------------- display
    Item {
        id: displayPage
        anchors.fill: parent
        visible: settings.page === "display"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "Display"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            InfoLine { width: parent.width; label: "Detected output"; value: settings.display.available ? settings.display.outputs[0].output : "none" }
            InfoLine { width: parent.width; label: "Native mode"; value: settings.display.resolution ? settings.display.resolution : "unknown" }

            Text { text: "Display mode"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            ActionList {
                id: displayModes
                width: parent.width
                height: Math.min(Theme.s(150), implicitHeight)
                actions: {
                    if (!settings.display.outputs) return []
                    const connected = settings.display.outputs.filter(function (output) { return output.status === "connected" })
                    if (connected.length === 0) return []
                    const modes = connected[0].modes || []
                    return modes.map(function (mode, index) {
                        return { label: mode, detail: index === 0 ? "native" : "" }
                    })
                }
                onTriggered: function (index) {
                    const connected = settings.display.outputs.filter(function (output) { return output.status === "connected" })
                    if (connected.length === 0) return
                    const mode = connected[0].modes[index]
                    settings.api("display.set_mode", { output: connected[0].output, mode: mode }, function () {
                        settings.flash("Display mode set to " + mode, false)
                        settings.loadDisplay()
                    }, 20000, function (message) { settings.flash(message, true) })
                }
                onNavigateDown: scaleActions.focusFirst()
            }

            Text { text: "Interface size"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            ActionList {
                id: scaleActions
                width: parent.width
                actions: [
                    { label: "100%", detail: "default" },
                    { label: "110%", detail: "larger text" },
                    { label: "125%", detail: "largest text" }
                ]
                onTriggered: function (index) {
                    AppSettings.uiScale = index === 0 ? 1.0 : (index === 1 ? 1.1 : 1.25)
                    settings.flash("Interface size updated", false)
                }
                onNavigateUp: displayModes.focusFirst()
                onNavigateDown: motionActions.focusFirst()
            }

            Text { text: "Motion"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            ActionList {
                id: motionActions
                width: parent.width
                height: Theme.s(128)
                actions: [
                    { label: "Full animations", detail: AppSettings.animations ? "current" : "" },
                    { label: "Reduced motion", detail: AppSettings.animations ? "" : "current" }
                ]
                onTriggered: function (index) {
                    AppSettings.animations = index === 0
                    settings.flash(index === 0 ? "Animations enabled" : "Animations reduced", false)
                }
                onNavigateUp: scaleActions.focusFirst()
                onNavigateDown: idleActions.focusFirst()
            }

            Text { text: "Idle screen"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            ActionList {
                id: idleActions
                width: parent.width
                height: Math.min(Theme.s(196), implicitHeight)
                actions: [
                    { label: "1 minute", detail: "" },
                    { label: "5 minutes", detail: "default" },
                    { label: "10 minutes", detail: "" },
                    { label: "30 minutes", detail: "" },
                    { label: "Never", detail: "" }
                ]
                onTriggered: function (index) {
                    const values = [1, 5, 10, 30, 0]
                    AppSettings.idleMinutes = values[index]
                    settings.flash("Idle screen updated", false)
                }
                onNavigateUp: motionActions.focusFirst()
            }
        }
    }

    // ----------------------------------------------------------- appearance
    Item {
        id: appearancePage
        anchors.fill: parent
        visible: settings.page === "appearance"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "Appearance"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: "Everything here is local to this television and applies immediately."
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
            }

            Row {
                width: parent.width
                height: parent.height - y
                spacing: Theme.s(36)

                Column {
                    width: (parent.width - Theme.s(36)) * 0.46
                    spacing: Theme.s(8)

                    Text { text: "Theme"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                    ActionList {
                        id: themeActions
                        width: parent.width
                        height: Theme.s(190)
                        actions: [
                            { label: "Aurora", detail: AppSettings.theme === "aurora" ? "current" : "cyan and violet" },
                            { label: "Midnight", detail: AppSettings.theme === "midnight" ? "current" : "high contrast blue-black" },
                            { label: "Warm", detail: AppSettings.theme === "warm" ? "current" : "amber and cream" }
                        ]
                        onTriggered: function (index) {
                            AppSettings.theme = index === 0 ? "aurora" : (index === 1 ? "midnight" : "warm")
                            settings.flash("Theme updated", false)
                        }
                        onNavigateUp: settings.requestHeaderFocus()
                        onNavigateDown: wallpaperActions.focusFirst()
                    }

                    Text { text: "Wallpaper"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                    ActionList {
                        id: wallpaperActions
                        width: parent.width
                        height: Theme.s(190)
                        actions: [
                            { label: "Aurora glow", detail: AppSettings.wallpaper === "aurora" ? "current" : "soft colour fields" },
                            { label: "Nebula", detail: AppSettings.wallpaper === "nebula" ? "current" : "violet night sky" },
                            { label: "Graphite", detail: AppSettings.wallpaper === "graphite" ? "current" : "neutral and quiet" }
                        ]
                        onTriggered: function (index) {
                            AppSettings.wallpaper = index === 0 ? "aurora" : (index === 1 ? "nebula" : "graphite")
                            settings.flash("Wallpaper updated", false)
                        }
                        onNavigateUp: themeActions.focusFirst()
                        onNavigateDown: rowActions.focusFirst()
                    }
                }

                Column {
                    width: parent.width - Theme.s(36) - (parent.width - Theme.s(36)) * 0.46
                    spacing: Theme.s(8)

                    Text { text: "Home rows"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                    ActionList {
                        id: rowActions
                        width: parent.width
                        height: Theme.s(252)
                        actions: [
                            { label: "Recently opened", detail: AppSettings.showRecent ? "shown" : "hidden" },
                            { label: "Your apps", detail: AppSettings.showFavorites ? "shown" : "hidden" },
                            { label: "Streaming", detail: AppSettings.showStreaming ? "shown" : "hidden" },
                            { label: "Installed applications", detail: AppSettings.showApps ? "shown" : "hidden" }
                        ]
                        onTriggered: function (index) {
                            if (index === 0) AppSettings.showRecent = !AppSettings.showRecent
                            else if (index === 1) AppSettings.showFavorites = !AppSettings.showFavorites
                            else if (index === 2) AppSettings.showStreaming = !AppSettings.showStreaming
                            else AppSettings.showApps = !AppSettings.showApps
                            settings.flash("Home row visibility updated", false)
                        }
                        onNavigateUp: wallpaperActions.focusFirst()
                        onNavigateDown: startActions.focusFirst()
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.s(16)

                        Column {
                            width: (parent.width - Theme.s(16)) / 2
                            spacing: Theme.s(6)
                            Text { text: "On launch"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                            ActionList {
                                id: startActions
                                width: parent.width
                                height: Theme.s(130)
                                actions: [
                                    { label: "Open Home", detail: AppSettings.startScreen === "home" ? "current" : "" },
                                    { label: "Open Apps", detail: AppSettings.startScreen === "apps" ? "current" : "" }
                                ]
                                onTriggered: function (index) {
                                    AppSettings.startScreen = index === 0 ? "home" : "apps"
                                    settings.flash("Start screen updated for the next launch", false)
                                }
                                onNavigateUp: rowActions.focusFirst()
                                onNavigateDown: clockActions.focusFirst()
                            }
                        }

                        Column {
                            width: (parent.width - Theme.s(16)) / 2
                            spacing: Theme.s(6)
                            Text { text: "Clock"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
                            ActionList {
                                id: clockActions
                                width: parent.width
                                height: Theme.s(130)
                                actions: [
                                    { label: "24-hour clock", detail: AppSettings.clock24h ? "current" : "" },
                                    { label: "12-hour clock", detail: AppSettings.clock24h ? "" : "current" }
                                ]
                                onTriggered: function (index) {
                                    AppSettings.clock24h = index === 0
                                    settings.flash("Clock format updated", false)
                                }
                                onNavigateUp: startActions.focusFirst()
                            }
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------- audio
    Item {
        id: audioPage
        anchors.fill: parent
        visible: settings.page === "audio"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "Audio"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            InfoLine { width: parent.width; label: "Output"; value: settings.audio.default ? settings.audio.default : "no output" }
            InfoLine { width: parent.width; label: "Volume"; value: settings.audio.available ? settings.audio.volume + "%" + (settings.audio.mute ? " (muted)" : "") : "—" }

            ActionList {
                id: audioActions
                width: parent.width
                actions: [
                    { label: "Volume up", detail: "+5%" },
                    { label: "Volume down", detail: "-5%" },
                    { label: settings.audio.mute ? "Unmute" : "Mute", detail: "" },
                    { label: "Play test sound", detail: "440 Hz, one second" }
                ]
                onTriggered: function (index) {
                    if (index === 0 || index === 1) {
                        const next = Math.max(0, Math.min(100, (settings.audio.volume || 0) + (index === 0 ? 5 : -5)))
                        settings.api("audio.set_volume", { volume: next }, function () { settings.loadAudio() })
                    } else if (index === 2) {
                        settings.api("audio.set_mute", { mute: !settings.audio.mute }, function () { settings.loadAudio() })
                    } else {
                        settings.api("audio.test", {}, function () { settings.flash("Test tone sent", false) }, 10000, function (m) { settings.flash(m, true) })
                    }
                }
                onNavigateDown: sinkActions.focusFirst()
            }

            Text { text: "Output device"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(15); font.weight: Font.DemiBold }
            ActionList {
                id: sinkActions
                width: parent.width
                actions: (settings.audio.sinks || []).map(function (sink) {
                    return { label: sink.description, detail: (sink.hdmi ? "HDMI" : "analog") + (sink.default ? " · current" : "") }
                })
                onTriggered: function (index) {
                    const sinks = settings.audio.sinks || []
                    if (!sinks[index]) return
                    settings.api("audio.set_output", { sink: sinks[index].name }, function () {
                        settings.flash("Audio output changed", false)
                        settings.loadAudio()
                    })
                }
                onNavigateUp: audioActions.focusFirst()
            }
        }
    }

    // -------------------------------------------------------- applications
    Item {
        id: applicationsPage
        anchors.fill: parent
        visible: settings.page === "applications"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "Applications"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            Text {
                text: "Enter adds or removes a favourite · H hides or restores · R removes a user web shortcut"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
            }

            ActionList {
                id: webActions
                width: parent.width
                actions: [{ label: "Add a web application", detail: "https:// only" }]
                onTriggered: if (index === 0) addNameDialog.open()
                onNavigateDown: appActions.focusFirst()
            }

            ActionList {
                id: appActions
                width: parent.width
                height: Math.min(Theme.s(430), implicitHeight)
                actions: catalog.allApps.map(function (app) {
                    return {
                        label: app.name,
                        detail: (app.hidden ? "hidden" : app.compatibility) + (app.favorite ? " · ★" : "")
                    }
                })
                property var currentApp: {
                    const list = catalog.allApps
                    return list[appActions.currentIndex] ? list[appActions.currentIndex] : null
                }
                onTriggered: function (index) {
                    const list = catalog.allApps
                    if (list[index]) catalog.toggleFavorite(list[index].id)
                }
                onNavigateUp: webActions.focusFirst()
                Keys.onPressed: function (event) {
                    const list = catalog.allApps
                    const app = list[appActions.currentIndex]
                    if (!app) return
                    if (event.key === Qt.Key_H) {
                        catalog.setHidden(app.id, !app.hidden)
                        event.accepted = true
                    } else if (event.key === Qt.Key_R && app.id.indexOf("web.user.") === 0) {
                        event.accepted = true
                        settings.askConfirm("Remove shortcut", "Remove “" + app.name + "” from the launcher?", "Remove", true, function () {
                            const error = catalog.removeWebApp(app.id)
                            if (error) settings.flash(error, true)
                        })
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- system
    Item {
        id: systemPage
        anchors.fill: parent
        visible: settings.page === "system"

        Column {
            anchors.fill: parent
            spacing: Theme.s(6)

            Text { text: "System"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            InfoLine { width: parent.width; label: "Product"; value: (settings.sysInfo.product || "PiVista TV") + " " + (settings.sysInfo.version || "") }
            InfoLine { width: parent.width; label: "Build"; value: settings.sysInfo.build_id || "—" }
            InfoLine { width: parent.width; label: "Model"; value: settings.sysInfo.model || "—" }
            InfoLine { width: parent.width; label: "Kernel"; value: settings.sysInfo.kernel || "—" }
            InfoLine { width: parent.width; label: "Uptime"; value: settings.fmtUptime(settings.sysStatus.uptime_s) }
            InfoLine { width: parent.width; label: "Temperature"; value: settings.sysStatus.temperature_c !== undefined && settings.sysStatus.temperature_c !== null ? settings.sysStatus.temperature_c + " °C" : "—" }
            InfoLine { width: parent.width; label: "Memory"; value: settings.sysStatus.memory ? settings.sysStatus.memory.used_percent + "% used" : "—" }
            InfoLine { width: parent.width; label: "Storage"; value: settings.sysStatus.storage ? settings.fmtBytes(settings.sysStatus.storage.free_bytes) + " free" : "—" }

            ActionList {
                id: systemActions
                width: parent.width
                actions: [
                    { label: "Export diagnostics", detail: "local file, no upload" },
                    { label: settings.showLogs ? "Hide recent logs" : "Show recent logs", detail: "session journal" },
                    { label: "Refresh", detail: "" }
                ]
                onTriggered: function (index) {
                    if (index === 0) {
                        settings.api("diagnostics.export", {}, function (data) {
                            settings.flash("Diagnostics written to " + data.path, false)
                        }, 30000, function (m) { settings.flash(m, true) })
                    } else if (index === 1) {
                        settings.showLogs = !settings.showLogs
                        if (settings.showLogs) {
                            settings.api("logs.tail", { unit: "session" }, function (data) { settings.logsText = data.text })
                        }
                    } else {
                        settings.loadSystem()
                    }
                }
            }

            Text {
                visible: settings.showLogs
                width: parent.width
                height: Theme.s(160)
                text: settings.formatLogTail(settings.logsText)
                color: Theme.textDim
                font.family: "monospace"
                font.pixelSize: Theme.s(11)
                wrapMode: Text.WrapAnywhere
                clip: true
            }
        }
    }

    // ------------------------------------------------------------ updates
    Item {
        id: updatesPage
        anchors.fill: parent
        visible: settings.page === "updates"

        Column {
            anchors.fill: parent
            spacing: Theme.s(6)

            Text { text: "Updates"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: "Launcher updates are signed, verified and can be rolled back without touching your settings. Debian package updates are separate and have no A/B rollback; a failed system update may require reflashing (docs/recovery.md)."
                color: Theme.warn
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
                wrapMode: Text.WordWrap
            }
            InfoLine { width: parent.width; label: "Launcher"; value: (settings.appUpdate.installed || "unknown") + (settings.appUpdate.available === true && settings.appUpdate.latest ? "  →  " + settings.appUpdate.latest : " (installed)") }
            InfoLine { width: parent.width; label: "Last checked"; value: settings.appUpdate.checked_at || "not checked" }
            InfoLine { width: parent.width; label: "Update state"; value: (settings.appUpdate.job && settings.appUpdate.job.message) ? settings.appUpdate.job.message : "idle" }
            InfoLine { width: parent.width; label: "Download"; value: settings.appUpdate.size ? settings.fmtBytes(settings.appUpdate.size) + " · SHA-256 verified" : "—" }
            InfoLine { width: parent.width; label: "System packages"; value: settings.update.state === "running" ? "installing…" : (settings.updateCheck.available !== undefined ? settings.updateCheck.available + " available" : "not checked") }

            Text {
                visible: settings.appUpdate.available === true && (settings.appUpdate.notes || "").length > 0
                width: parent.width
                height: visible ? Theme.s(54) : 0
                text: settings.appUpdate.available ? settings.appUpdate.notes : ""
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                clip: true
            }

            Text {
                visible: (settings.appUpdate.reason || "").length > 0 && settings.appUpdate.available !== true
                width: parent.width
                text: settings.appUpdate.reason || ""
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
                wrapMode: Text.WordWrap
            }

            Rectangle {
                visible: settings.appUpdate.job && (settings.appUpdate.job.state === "downloading" || settings.appUpdate.job.state === "installing")
                width: parent.width
                height: Theme.s(8)
                radius: Theme.s(4)
                color: Theme.surfaceHigh

                Rectangle {
                    width: parent.width * Math.min(100, Math.max(0, (settings.appUpdate.job.progress || 0))) / 100
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                }
            }

            Text {
                visible: settings.appUpdate.job && settings.appUpdate.job.state === "failed"
                width: parent.width
                text: "Update error: " + ((settings.appUpdate.job && settings.appUpdate.job.error) || "unknown error")
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
                wrapMode: Text.WordWrap
            }

            ActionList {
                id: updateActions
                width: parent.width
                height: Math.min(Theme.s(382), implicitHeight)
                actions: settings.appUpdateActionItems()
                onTriggered: function (index) { settings.handleAppUpdateAction(index) }
            }

            Text {
                visible: settings.showLogs
                width: parent.width
                height: Theme.s(120)
                text: settings.formatLogTail(settings.logsText)
                color: Theme.textDim
                font.family: "monospace"
                font.pixelSize: Theme.s(10)
                wrapMode: Text.WrapAnywhere
                clip: true
            }
        }
    }

    // ------------------------------------------------------------ privacy
    Item {
        id: privacyPage
        anchors.fill: parent
        visible: settings.page === "privacy"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "Privacy and security"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: "PiVista TV has no telemetry and uploads nothing. Diagnostics are written locally and must be copied off the device deliberately. Browser profiles contain streaming sessions and are stored in the pivista account's home directory."
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
                wrapMode: Text.WordWrap
            }
            InfoLine { width: parent.width; label: "Android runtime"; value: settings.android.state || "not checked" }
            Text {
                width: parent.width
                text: (settings.android.reasons || []).join(" · ")
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
                wrapMode: Text.WordWrap
            }

            ActionList {
                id: privacyActions
                width: parent.width
                actions: [
                    { label: "Clear browser data", detail: "removes cookies and sessions" },
                    { label: "Check Android compatibility", detail: "diagnostic only" },
                    { label: "Run first-time setup", detail: "reopens the wizard" },
                    { label: "Factory reset information", detail: "" }
                ]
                onTriggered: function (index) {
                    if (index === 0) {
                        settings.askConfirm("Clear browser data",
                            "This removes all Chromium profiles: cookies, streaming sessions and history. Account passwords are not stored by PiVista TV.",
                            "Clear", true, function () {
                                catalog.clearBrowserData()
                                settings.flash("Browser data cleared", false)
                            })
                    } else if (index === 1) {
                        settings.loadAndroid()
                        settings.flash("Android status refreshed", false)
                    } else if (index === 2) {
                        AppSettings.setupComplete = false
                    } else {
                        settings.flash("Factory reset means reflashing the image; see docs/recovery.md", false)
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------- about
    Item {
        id: aboutPage
        anchors.fill: parent
        visible: settings.page === "about"

        Column {
            anchors.fill: parent
            spacing: Theme.s(10)

            Text { text: "About PiVista TV"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            InfoLine { width: parent.width; label: "Launcher"; value: (settings.appUpdate.installed || settings.sysInfo.app_version || "unknown") }
            InfoLine { width: parent.width; label: "Image"; value: (settings.sysInfo.version || "—") + " “" + (settings.sysInfo.codename || "—") + "”" }
            InfoLine { width: parent.width; label: "Build"; value: settings.sysInfo.build_id || "development" }
            InfoLine { width: parent.width; label: "Model"; value: settings.sysInfo.model || "Raspberry Pi 5" }
            InfoLine { width: parent.width; label: "Kernel"; value: settings.sysInfo.kernel || "—" }
            Text {
                width: parent.width
                text: "PiVista TV is free software built on Raspberry Pi OS and Debian. Licences for every installed package are in /usr/share/doc. The launcher is GPL-3.0; the product name and artwork are original."
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: "This is an independent project. It is not affiliated with, endorsed by or certified by Netflix, Disney, Google, Raspberry Pi Ltd or any streaming provider."
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
                wrapMode: Text.WordWrap
            }

            ActionList {
                id: aboutActions
                width: parent.width
                actions: [{ label: "Back to settings", detail: "" }]
                onTriggered: settings.closePage()
            }
        }
    }

    // -------------------------------------------------------------- status
    Rectangle {
        visible: settings.notice.length > 0
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, noticeText.implicitWidth + Theme.s(44))
        height: Theme.s(46)
        radius: Theme.s(12)
        color: settings.noticeIsError ? "#3b1116" : Theme.surfaceHigh
        border.width: Theme.s(1)
        border.color: settings.noticeIsError ? Theme.danger : Theme.accentDim

        Text {
            id: noticeText
            anchors.centerIn: parent
            text: settings.notice
            color: settings.noticeIsError ? Theme.danger : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(14)
            elide: Text.ElideRight
            width: parent.width - Theme.s(30)
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // -------------------------------------------------------------- dialogs
    TextEntryDialog {
        id: wifiDialog
        title: "Wi-Fi password"
        mask: true
        onAccepted: function (text) { settings.connectWifi(text) }
        onCancelled: {
            close()
            netActions.focusFirst()
        }
    }

    TextEntryDialog {
        id: addNameDialog
        title: "New web application"
        hint: "Give the shortcut a name."
        onAccepted: function (text) {
            if (text.trim().length === 0) {
                fail("Enter a name.")
                return
            }
            close()
            addUrlDialog.enteredName = text.trim()
            addUrlDialog.open()
        }
        onCancelled: {
            close()
            webActions.focusFirst()
        }
    }

    TextEntryDialog {
        id: addUrlDialog
        property string enteredName: ""
        title: "Web address"
        hint: "Only https:// addresses are accepted. Playback depends on the site and its DRM policy."
        onAccepted: function (text) {
            const error = catalog.addWebApp(enteredName, text)
            if (error.length > 0) {
                fail(error)
                return
            }
            close()
            settings.flash("Shortcut added", false)
            appActions.focusFirst()
        }
        onCancelled: {
            close()
            webActions.focusFirst()
        }
    }

    ConfirmDialog {
        id: confirmDialog
        onConfirmed: {
            close()
            if (settings.pendingConfirm) {
                const callback = settings.pendingConfirm
                settings.pendingConfirm = null
                callback()
            }
        }
        onCancelled: {
            close()
            settings.pendingConfirm = null
        }
    }

    Keys.onEscapePressed: {
        if (settings.page !== "")
            settings.closePage()
        else
            settings.requestHeaderFocus()
    }

    onPageChanged: {
        if (page !== "" && page !== undefined)
            loadPage()
    }
}
