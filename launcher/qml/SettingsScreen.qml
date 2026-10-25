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

    function loadAndroid() {
        api("android.status", {}, function (data) { android = data })
    }

    function loadPage() {
        if (page === "network") loadNetwork()
        else if (page === "display") loadDisplay()
        else if (page === "audio") loadAudio()
        else if (page === "system") loadSystem()
        else if (page === "updates") { loadUpdate(); loadUpdateHistory() }
        else if (page === "privacy") { loadAndroid() }
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
        if (page === "network") netActions.focusFirst()
        else if (page === "display") displayModes.focusFirst()
        else if (page === "audio") audioActions.focusFirst()
        else if (page === "applications") appActions.focusFirst()
        else if (page === "system") systemActions.focusFirst()
        else if (page === "updates") updateActions.focusFirst()
        else if (page === "privacy") privacyActions.focusFirst()
        else if (page === "about") aboutActions.focusFirst()
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

    Component.onCompleted: loadUpdate()

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
                    { label: settings.net.wifi_connected ? "Disconnect Wi-Fi" : "Wi-Fi not connected", detail: settings.net.wifi_connected ? settings.net.connection : "" },
                    { label: "Test internet connection", detail: "DNS and NetworkManager" },
                    { label: "Refresh status", detail: "" }
                ]
                onTriggered: function (index) {
                    if (index === 0) settings.scanWifi()
                    else if (index === 1) settings.api("network.disconnect", { device: settings.net.interface }, function () { settings.flash("Disconnected", false); settings.loadNetwork() }, 30000, function (m) { settings.flash(m, true) })
                    else if (index === 2) { settings.loadNetwork(); settings.flash("Connectivity test requested", false) }
                    else settings.loadNetwork()
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
            spacing: Theme.s(10)

            Text { text: "Updates"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(26); font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: "Updates use Debian packages from the sources pinned in this image. There is no A/B rollback: if an update fails, reflash a known-good image. This is documented in docs/recovery.md."
                color: Theme.warn
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
                wrapMode: Text.WordWrap
            }
            InfoLine { width: parent.width; label: "State"; value: settings.update.state || "idle" }
            InfoLine { width: parent.width; label: "Available"; value: settings.updateCheck.available !== undefined ? settings.updateCheck.available + " packages" : "not checked" }

            ActionList {
                id: updateActions
                width: parent.width
                actions: [
                    { label: "Check for updates", detail: "network required" },
                    { label: "Install updates", detail: "experimental" },
                    { label: settings.showLogs ? "Hide update log" : "Show update log", detail: "" },
                    { label: "Refresh status", detail: "" }
                ]
                onTriggered: function (index) {
                    if (index === 0) {
                        settings.flash("Checking for updates…", false)
                        settings.api("update.check", {}, function (data) {
                            settings.updateCheck = data
                            settings.flash(data.available + " updates available", false)
                        }, 240000, function (m) { settings.flash(m, true) })
                    } else if (index === 1) {
                        settings.askConfirm("Install updates",
                            "The system will download and install package updates. Do not power off. There is no automatic rollback.",
                            "Install", true, function () {
                                settings.api("update.apply", { confirm: true }, function () {
                                    settings.flash("Update started", false)
                                    settings.loadUpdate()
                                }, 30000, function (m) { settings.flash(m, true) })
                            })
                    } else if (index === 2) {
                        settings.showLogs = !settings.showLogs
                        settings.loadUpdateHistory()
                    } else {
                        settings.loadUpdate()
                    }
                }
            }

            Text {
                visible: settings.showLogs
                width: parent.width
                height: Theme.s(170)
                text: settings.formatLogTail(settings.logsText)
                color: Theme.textDim
                font.family: "monospace"
                font.pixelSize: Theme.s(11)
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
            InfoLine { width: parent.width; label: "Version"; value: (settings.sysInfo.version || "0.1.0") + " “" + (settings.sysInfo.codename || "Aurora") + "”" }
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
