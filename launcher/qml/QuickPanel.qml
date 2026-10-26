import QtQuick

FocusScope {
    id: panel
    anchors.fill: parent
    visible: false
    z: 50

    property var audio: ({})
    property var net: ({})
    property var pending: ({})
    property var pendingConfirm: null
    property int sleepMinutes: 0
    property int sleepRemaining: 0

    signal closed()
    signal sleepTimerRequested(int minutes)

    function api(action, params, onOk, timeout, onErr) {
        const id = control.call(action, params, timeout === undefined ? 20000 : timeout)
        pending[id] = { ok: onOk, err: onErr }
    }

    function load() {
        api("audio.status", {}, function (data) { audio = data })
        api("network.status", {}, function (data) { net = data })
    }

    function open() {
        visible = true
        load()
        Qt.callLater(function () { actions.focusFirst() })
    }

    function close() {
        visible = false
        closed()
    }

    function askConfirm(title, message, label, callback) {
        pendingConfirm = callback
        confirm.title = title
        confirm.message = message
        confirm.confirmLabel = label
        confirm.open()
    }

    Connections {
        target: control
        function onResponse(id, data) {
            const handler = panel.pending[id]
            if (handler) {
                delete panel.pending[id]
                if (handler.ok) handler.ok(data)
            }
        }
        function onFailed(id, code, message) {
            const handler = panel.pending[id]
            if (handler) {
                delete panel.pending[id]
                if (handler.err) handler.err(message)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.02, 0.05, 0.66)
        MouseArea {
            anchors.fill: parent
            onClicked: panel.close()
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Theme.s(520)
        color: Theme.bgRaised
        border.width: Theme.s(1)
        border.color: Qt.rgba(1, 1, 1, 0.10)

        Column {
            anchors.fill: parent
            anchors.margins: Theme.s(34)
            spacing: Theme.s(16)

            Text {
                text: "Quick settings"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(26)
                font.weight: Font.DemiBold
            }

            Text {
                text: (panel.net.connection ? panel.net.connection : "offline")
                      + (panel.net.ip ? " · " + panel.net.ip : "")
                color: panel.net.connected ? Theme.good : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
            }

            Rectangle {
                width: parent.width
                height: Theme.s(104)
                radius: Theme.s(16)
                color: Theme.surface

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.s(4)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.audio.mute ? "Muted" : ((panel.audio.volume !== undefined ? panel.audio.volume : 0) + "%")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(34)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.audio.hdmi ? "HDMI output" : (panel.audio.default || "no output")
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(12)
                    }
                }
            }

            ActionList {
                id: actions
                width: parent.width
                actions: [
                    { label: "Volume up", detail: "+5%" },
                    { label: "Volume down", detail: "-5%" },
                    { label: panel.audio.mute ? "Unmute" : "Mute", detail: "" },
                    { label: "Sleep timer", detail: panel.sleepMinutes > 0
                                                    ? (Math.floor(panel.sleepRemaining / 60) + ":"
                                                       + ("0" + (panel.sleepRemaining % 60)).slice(-2) + " remaining")
                                                    : "off · 30 / 60 / 90 min" },
                    { label: "Restart", detail: "safe reboot" },
                    { label: "Shut down", detail: "power off" },
                    { label: "Close", detail: "" }
                ]
                onTriggered: function (index) {
                    if (index === 0 || index === 1) {
                        const next = Math.max(0, Math.min(100, (panel.audio.volume || 0) + (index === 0 ? 5 : -5)))
                        panel.api("audio.set_volume", { volume: next }, function () { panel.load() })
                    } else if (index === 2) {
                        panel.api("audio.set_mute", { mute: !panel.audio.mute }, function () { panel.load() })
                    } else if (index === 3) {
                        const next = panel.sleepMinutes === 0 ? 30
                                   : (panel.sleepMinutes === 30 ? 60
                                   : (panel.sleepMinutes === 60 ? 90 : 0))
                        panel.sleepTimerRequested(next)
                    } else if (index === 4) {
                        panel.askConfirm("Restart", "Restart PiVista TV now?", "Restart", function () {
                            panel.api("power.reboot", { confirm: true }, function () { panel.close() })
                        })
                    } else if (index === 5) {
                        panel.askConfirm("Shut down", "Power off safely? The screen will go blank.", "Shut down", function () {
                            panel.api("power.shutdown", { confirm: true }, function () { panel.close() })
                        })
                    } else {
                        panel.close()
                    }
                }
            }

            Text {
                width: parent.width
                text: "Settings → Network for Wi-Fi, Display for resolution and Audio for output devices."
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
                wrapMode: Text.WordWrap
            }
        }
    }

    ConfirmDialog {
        id: confirm
        onConfirmed: {
            close()
            if (panel.pendingConfirm) {
                const callback = panel.pendingConfirm
                panel.pendingConfirm = null
                callback()
            }
        }
        onCancelled: {
            close()
            panel.pendingConfirm = null
            actions.focusFirst()
        }
    }

    Keys.onEscapePressed: panel.close()
    onVisibleChanged: if (!visible) pending = ({})
}
