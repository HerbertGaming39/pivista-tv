import QtQuick

Item {
    id: wizard
    anchors.fill: parent
    z: 40
    visible: !AppSettings.setupComplete && !uiDevMode

    // Development-only override used by the offscreen layout test.
    property int step: (typeof uiWizardStep !== "undefined"
                        && uiWizardStep > 0 && uiWizardStep < 8) ? uiWizardStep : 0
    property string language: "English (United Kingdom)"
    property string locale: "en_GB.UTF-8"
    property string timezone: "Europe/Warsaw"
    property var network: ({})
    property var wifi: []
    property var display: ({})
    property var audio: ({})
    property var pending: ({})
    property string wifiSsid: ""
    property string message: ""
    property bool messageIsError: false
    property string setupWarning: ""
    property bool finishing: false

    signal completed()

    function notify(text, isError) {
        message = text
        messageIsError = isError === true
        messageTimer.restart()
    }

    readonly property var timezones: [
        "Europe/Warsaw", "Europe/London", "Europe/Berlin", "Europe/Paris",
        "Europe/Madrid", "Europe/Rome", "Europe/Kyiv", "UTC", "America/New_York"
    ]

    function api(action, params, onOk, timeout, onErr) {
        const id = control.call(action, params, timeout === undefined ? 30000 : timeout)
        pending[id] = { ok: onOk, err: onErr }
    }

    function refreshNetwork() {
        api("network.status", {}, function (data) { network = data })
    }

    function scanWifi() {
        api("network.scan", { rescan: true }, function (data) {
            wifi = data.networks || []
            if (wifi.length > 0) wifiList.focusFirst()
        }, 60000, function (message) { wizard.notify(message, true) })
    }

    function connectWifi(ssid, secure) {
        wifiSsid = ssid
        if (secure) {
            wifiDialog.hint = "Password for " + ssid
            wifiDialog.open()
        } else {
            doConnect("")
        }
    }

    function doConnect(password) {
        api("network.connect", { ssid: wifiSsid, password: password }, function () {
            wifiDialog.close()
            status.text = "Connected to " + wifiSsid
            wizard.notify("Connected to " + wifiSsid, false)
            refreshNetwork()
        }, 90000, function (message) {
            if (wifiDialog.visible) wifiDialog.fail(message)
            else wizard.notify(message, true)
        })
    }

    function loadDisplay() { api("display.status", {}, function (data) { display = data }) }
    function loadAudio() { api("audio.status", {}, function (data) { audio = data }) }

    function focusStep() {
        let focused = false
        if (step === 0) focused = navActions.focusAt(0)
        else if (step === 1) focused = languageList.focusFirst()
        else if (step === 2) focused = networkActions.focusFirst()
        else if (step === 3) focused = displayList.focusFirst()
        else if (step === 4) focused = audioList.focusFirst()
        // A display/audio probe can legitimately return no entries (no HDMI,
        // no sink yet). Never leave the remote with nowhere to focus.
        if (!focused)
            navActions.focusAt(0)
    }

    function next() {
        if (step < 7) {
            step++
        } else {
            finish()
        }
    }

    function back() {
        if (step > 0)
            step--
        else
            navActions.focusAt(0)
    }

    function finish() {
        if (finishing)
            return
        finishing = true
        setupWarning = ""
        AppSettings.locale = locale
        AppSettings.timezone = timezone
        AppSettings.privacyAccepted = true
        wizard.notify("Applying time zone and locale…", false)

        let remaining = 2
        function complete() {
            if (--remaining > 0)
                return
            finishing = false
            AppSettings.setupComplete = true
            wizard.completed()
        }
        function failed(label) {
            return function (message) {
                setupWarning = label + ": " + message
                complete()
            }
        }
        // Setup must not dead-end when the control service is unavailable.
        // The wizard still completes; Main shows any warning after it closes.
        api("system.set_timezone", { timezone: timezone }, complete, 15000,
            failed("Time zone not applied"))
        api("system.set_locale", { locale: locale }, complete, 15000,
            failed("Locale not applied"))
    }

    onVisibleChanged: if (visible) {
        message = ""
        if (AppSettings.timezone.length > 0)
            timezone = AppSettings.timezone
        if (AppSettings.locale === "pl_PL.UTF-8") {
            language = "Polski (Poland)"
            locale = "pl_PL.UTF-8"
        }
        Qt.callLater(focusStep)
    }

    onStepChanged: {
        if (step === 2) refreshNetwork()
        else if (step === 3) loadDisplay()
        else if (step === 4) loadAudio()
        Qt.callLater(focusStep)
    }

    Component.onCompleted: {
        refreshNetwork()
        loadDisplay()
        Qt.callLater(focusStep)
    }

    Connections {
        target: control
        function onResponse(id, data) {
            const handler = wizard.pending[id]
            if (handler) {
                delete wizard.pending[id]
                if (handler.ok) handler.ok(data)
            }
        }
        function onFailed(id, code, message) {
            const handler = wizard.pending[id]
            if (handler) {
                delete wizard.pending[id]
                if (handler.err) handler.err(message)
                else wizard.notify(message, true)
            }
        }
    }

    Timer {
        id: messageTimer
        interval: 9000
        onTriggered: wizard.message = ""
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bgDeep

        // Ambient accent, kept subtle behind the setup card.
        Rectangle {
            width: Theme.s(700)
            height: width
            radius: width / 2
            x: -Theme.s(220)
            y: -Theme.s(280)
            color: Qt.rgba(0.43, 0.91, 0.98, 0.08)
        }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.s(1080)
            // Tall enough for the language/time-zone step at both 1080p and
            // 720p; the previous 720-unit card clipped the Back button.
            height: Theme.s(840)
            radius: Theme.s(28)
            color: Theme.bgRaised
            border.width: Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Column {
                anchors.fill: parent
                anchors.margins: Theme.s(44)
                spacing: Theme.s(16)

                Item {
                    width: parent.width
                    height: Theme.s(64)
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "PiVista"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(30)
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.s(118)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TV"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(30)
                        font.weight: Font.Bold
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(8)
                        Repeater {
                            model: 8
                            Rectangle {
                                width: Theme.s(8)
                                height: Theme.s(8)
                                radius: Theme.s(4)
                                color: index === wizard.step ? Theme.accent
                                     : (index < wizard.step ? Theme.accentDim : Theme.surfaceHigh)
                            }
                        }
                    }
                }

                // -------------------------------------------------- welcome
                Column {
                    width: parent.width
                    visible: wizard.step === 0
                    spacing: Theme.s(18)
                    Text {
                        text: "Your television, without the computer"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(34)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: "PiVista TV starts straight into a full-screen interface built for a remote control. This short setup configures language, network, display and audio. You can change everything later in Settings."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(17)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: "No account is required. No telemetry is collected."
                        color: Theme.good
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(15)
                    }
                }

                // --------------------------------------------------- region
                Column {
                    width: parent.width
                    visible: wizard.step === 1
                    spacing: Theme.s(10)
                    Text { text: "Language and time zone"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        text: "The interface is currently English. The locale and time zone apply to dates, numbers and the clock."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                    }
                    ActionList {
                        id: languageList
                        width: parent.width
                        actions: [
                            { label: "English (United Kingdom)", detail: "en_GB" },
                            { label: "Polski (Poland)", detail: "pl_PL" }
                        ]
                        onTriggered: function (index) {
                            if (index === 0) { wizard.language = "English (United Kingdom)"; wizard.locale = "en_GB.UTF-8" }
                            else { wizard.language = "Polski (Poland)"; wizard.locale = "pl_PL.UTF-8" }
                            timezoneList.focusFirst()
                        }
                        onNavigateDown: timezoneList.focusFirst()
                    }
                    ActionList {
                        id: timezoneList
                        width: parent.width
                        height: Math.min(Theme.s(250), implicitHeight)
                        actions: wizard.timezones.map(function (zone) { return { label: zone, detail: "" } })
                        onTriggered: function (index) {
                            wizard.timezone = wizard.timezones[index]
                            navActions.focusAt(0)
                        }
                        onNavigateUp: languageList.focusFirst()
                        onNavigateDown: navActions.focusAt(0)
                    }
                }

                // -------------------------------------------------- network
                Column {
                    width: parent.width
                    visible: wizard.step === 2
                    spacing: Theme.s(10)
                    Text { text: "Network"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        id: status
                        width: parent.width
                        text: wizard.network.connected
                              ? "Connected via " + (wizard.network.connection ? wizard.network.connection : wizard.network.interface) + " · " + (wizard.network.ip || "")
                              : "Not connected. You can continue offline; streaming needs a network."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                        wrapMode: Text.WordWrap
                    }
                    ActionList {
                        id: networkActions
                        width: parent.width
                        actions: [
                            { label: "Scan for Wi-Fi networks", detail: "Ethernet is used automatically" },
                            { label: "Continue without network", detail: "configure later in Settings" }
                        ]
                        onTriggered: function (index) {
                            if (index === 0) wizard.scanWifi()
                            else navActions.focusAt(0)
                        }
                        onNavigateDown: if (wifiList.actions.length > 0) wifiList.focusFirst(); else navActions.focusAt(0)
                    }
                    Text {
                        visible: wizard.wifi.length === 0
                        width: parent.width
                        text: "No Wi-Fi networks listed yet. Select Scan, or connect Ethernet and continue."
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                        wrapMode: Text.WordWrap
                    }
                    ActionList {
                        id: wifiList
                        visible: wizard.wifi.length > 0
                        width: parent.width
                        height: Math.min(Theme.s(200), implicitHeight)
                        actions: wizard.wifi.map(function (network) {
                            return { label: network.ssid, detail: (network.secure ? "locked" : "open") + " · " + network.signal + "%" }
                        })
                        onTriggered: function (index) {
                            const network = wizard.wifi[index]
                            if (network) wizard.connectWifi(network.ssid, network.secure)
                        }
                        onNavigateUp: networkActions.focusFirst()
                        onNavigateDown: navActions.focusAt(0)
                    }
                }

                // -------------------------------------------------- display
                Column {
                    width: parent.width
                    visible: wizard.step === 3
                    spacing: Theme.s(10)
                    Text { text: "Display"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: wizard.display.available
                              ? "Detected " + wizard.display.outputs[0].output + " at " + (wizard.display.resolution || "unknown") + ". Choose a mode only if the picture is wrong."
                              : "No display information is available yet."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        text: displayList.actions.length > 0 ? "Display mode" : "Display mode · no modes detected"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                        font.weight: Font.DemiBold
                    }
                    ActionList {
                        id: displayList
                        visible: actions.length > 0
                        width: parent.width
                        height: Math.min(Theme.s(170), implicitHeight)
                        actions: {
                            if (!wizard.display.outputs) return []
                            const connected = wizard.display.outputs.filter(function (output) { return output.status === "connected" })
                            if (connected.length === 0) return []
                            return connected[0].modes.map(function (mode, index) {
                                return { label: mode, detail: index === 0 ? "native" : "" }
                            })
                        }
                        onTriggered: function (index) {
                            const connected = wizard.display.outputs.filter(function (output) { return output.status === "connected" })
                            if (connected.length === 0) return
                            wizard.api("display.set_mode", { output: connected[0].output, mode: connected[0].modes[index] }, function () {
                                status.text = "Display mode updated"
                            }, 20000, function (message) { status.text = message })
                        }
                        onNavigateDown: scaleList.focusFirst()
                    }
                    Text { text: "Interface size"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.s(14); font.weight: Font.DemiBold }
                    ActionList {
                        id: scaleList
                        width: parent.width
                        actions: [
                            { label: "100%", detail: AppSettings.uiScale === 1.0 ? "current" : "" },
                            { label: "110%", detail: AppSettings.uiScale === 1.1 ? "current" : "" },
                            { label: "125%", detail: AppSettings.uiScale === 1.25 ? "current" : "" }
                        ]
                        onTriggered: function (index) {
                            AppSettings.uiScale = index === 0 ? 1.0 : (index === 1 ? 1.1 : 1.25)
                        }
                        onNavigateUp: displayList.focusFirst()
                        onNavigateDown: navActions.focusAt(0)
                    }
                }

                // --------------------------------------------------- audio
                Column {
                    width: parent.width
                    visible: wizard.step === 4
                    spacing: Theme.s(10)
                    Text { text: "Audio"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: wizard.audio.available
                              ? "Current output: " + (wizard.audio.default || "unknown") + (wizard.audio.hdmi ? " (HDMI)" : "")
                              : "No audio output detected."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                        wrapMode: Text.WordWrap
                    }
                    ActionList {
                        id: audioList
                        width: parent.width
                        height: Math.min(Theme.s(260), implicitHeight)
                        actions: (wizard.audio.sinks || []).map(function (sink) {
                            return { label: sink.description, detail: (sink.hdmi ? "HDMI" : "analog") + (sink.default ? " · current" : "") }
                        })
                        onTriggered: function (index) {
                            const sinks = wizard.audio.sinks || []
                            if (!sinks[index]) return
                            wizard.api("audio.set_output", { sink: sinks[index].name }, function () {
                                wizard.loadAudio()
                                status.text = "Audio output changed"
                            })
                        }
                        onNavigateDown: navActions.focusAt(0)
                    }
                    ActionList {
                        width: parent.width
                        actions: [{ label: "Play a test sound", detail: "440 Hz" }]
                        onTriggered: wizard.api("audio.test", {}, function () { status.text = "Test tone sent" }, 10000, function (message) { status.text = message })
                    }
                }

                // -------------------------------------------------- remote
                Column {
                    width: parent.width
                    visible: wizard.step === 5
                    spacing: Theme.s(12)
                    Text { text: "Remote and keyboard"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: "PiVista TV accepts USB keyboards, USB/IR media remotes that send standard key codes, and game controllers. Use the arrow keys or D-pad to move, Enter or OK to select, Back/Escape to return, and Home to leave any app. Bluetooth hardware is present, but this release has no Bluetooth pairing screen; use USB for setup."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(15)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: "HDMI-CEC is not enabled by default because it is unverified on Raspberry Pi 5. If your television remote does nothing, use a USB keyboard or USB/IR remote. Unusual buttons can be mapped in /etc/pivista/input.map from a text console."
                        color: Theme.warn
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(14)
                        wrapMode: Text.WordWrap
                    }
                }

                // ------------------------------------------------- privacy
                Column {
                    width: parent.width
                    visible: wizard.step === 6
                    spacing: Theme.s(12)
                    Text { text: "Privacy and updates"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: "No account is required and PiVista TV does not collect telemetry. Browser profiles, Wi-Fi credentials and settings stay on this device; diagnostics are written locally and never uploaded."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(15)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: "Update checks run only when you ask for them in Settings. Nothing is downloaded or installed automatically, and there is no automatic rollback: a failed update is recovered by reflashing a known-good image. The optional Android runtime is not installed."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(15)
                        wrapMode: Text.WordWrap
                    }
                }

                // ------------------------------------------------- finish
                Column {
                    width: parent.width
                    visible: wizard.step === 7
                    spacing: Theme.s(16)
                    Text { text: "Ready"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.s(28); font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: "PiVista TV will start on the home screen. No account has been created and no data leaves this device.\n\nLanguage: " + wizard.language + "\nTime zone: " + wizard.timezone + "\nNetwork: " + (wizard.network.connected ? (wizard.network.connection || wizard.network.interface) : "offline") + "\n\nNetflix and Disney+ open in Chromium and depend on Widevine L3. Their maximum resolution is not guaranteed and is documented honestly in the project's streaming notes."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(15)
                        wrapMode: Text.WordWrap
                    }
                }

                ActionList {
                    id: navActions
                    width: parent.width
                    height: Math.min(Theme.s(128), implicitHeight)
                    actions: [
                        { label: wizard.step === 7 ? "Start using PiVista TV" : "Continue", detail: "" },
                        { label: "Back", detail: "" }
                    ]
                    onTriggered: function (index) {
                        if (index === 0) wizard.next()
                        else wizard.back()
                    }
                    onNavigateUp: wizard.focusStep()
                }

                Text {
                    text: "Navigate with the arrow keys or remote · Enter selects · Escape goes back"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                }
            }
        }
    }

    Rectangle {
        id: messageBanner
        visible: wizard.message.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.s(24)
        width: Math.min(parent.width - Theme.s(48), messageText.implicitWidth + Theme.s(48))
        height: Theme.s(46)
        radius: Theme.s(12)
        color: wizard.messageIsError ? "#3b1116" : Theme.surfaceHigh
        border.width: Theme.s(1)
        border.color: wizard.messageIsError ? Theme.danger : Theme.accentDim
        z: 60

        Text {
            id: messageText
            anchors.centerIn: parent
            width: parent.width - Theme.s(30)
            text: wizard.message
            color: wizard.messageIsError ? Theme.danger : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(14)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }

    TextEntryDialog {
        id: wifiDialog
        title: "Wi-Fi password"
        mask: true
        onAccepted: function (text) { wizard.doConnect(text) }
        onCancelled: { close(); networkActions.focusFirst() }
    }

    Keys.onEscapePressed: if (wizard.step > 0) wizard.back()
}
