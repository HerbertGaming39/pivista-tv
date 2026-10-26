import QtQuick

// Full-screen key probe for Settings > Input. It exists because a television
// can show a perfectly drawn wizard while every remote key is going to the TV,
// not the Pi. This overlay proves which key codes actually reached the
// launcher and makes an undetected keyboard obvious before setup continues.
FocusScope {
    id: dialog
    anchors.fill: parent
    visible: false
    focus: visible
    z: 80

    property string lastKey: ""
    property string lastText: ""
    property int keyCount: 0

    signal closed()

    function open() {
        visible = true
        lastKey = ""
        lastText = ""
        keyCount = 0
        forceActiveFocus()
    }

    function close() {
        visible = false
        closed()
    }

    function keyName(key) {
        const names = {
            16777219: "Left",
            16777220: "Right",
            16777221: "Up",
            16777222: "Down",
            16777235: "Home",
            16777236: "End",
            16777237: "Page Down",
            16777238: "Page Up",
            16777216: "Escape",
            16777217: "Tab",
            16777218: "Backtab",
            16777223: "Delete",
            16777224: "Backspace",
            16777225: "Return",
            16777226: "Enter",
            16777227: "Insert",
            16777232: "Menu",
            16777233: "Pause",
            16777234: "Print",
            16777264: "F1",
            16777330: "F10",
            16777344: "Volume Up",
            16777345: "Volume Down",
            16777346: "Volume Mute",
            16777347: "Play",
            16777348: "Stop",
            16777349: "Previous",
            16777350: "Next",
            16777351: "Record",
            16777352: "Rewind",
            16777353: "Fast Forward",
            16777354: "Media",
            16777355: "Home Page",
            16777356: "Back",
            16777357: "Forward",
            16777358: "Stop",
            16777359: "Refresh",
            16777360: "Sleep"
        }
        return names[key] || ("Key " + key)
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.005, 0.01, 0.03, 0.88)
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.s(80), Theme.s(760))
        height: Theme.s(390)
        radius: Theme.s(22)
        color: Theme.bgRaised
        border.width: Theme.s(2)
        border.color: keyCount > 0 ? Theme.accent : Theme.surfaceHigh

        Behavior on border.color {
            ColorAnimation { duration: Theme.animShort }
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.s(34)
            spacing: Theme.s(15)

            Text {
                text: "Input test"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(28)
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: keyCount === 0
                      ? "Press any key on the remote or keyboard. Nothing else will happen while this is open."
                      : "Keys are reaching PiVista. Press Escape or Back when you have seen enough."
                color: keyCount === 0 ? Theme.textDim : Theme.good
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(15)
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: Theme.s(126)
                radius: Theme.s(14)
                color: Theme.surface

                Text {
                    anchors.centerIn: parent
                    width: parent.width - Theme.s(30)
                    text: keyCount === 0 ? "Waiting for a key…" : lastKey
                    color: keyCount === 0 ? Theme.textFaint : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: keyCount === 0 ? Theme.s(22) : Theme.s(34)
                    font.weight: keyCount === 0 ? Font.Normal : Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                text: lastText.length > 0
                      ? "Text: “" + lastText + "”  ·  " + keyCount + " key" + (keyCount === 1 ? "" : "s") + " received"
                      : (keyCount > 0 ? keyCount + " key" + (keyCount === 1 ? "" : "s") + " received" : "Device: shown by the kernel in the list behind this dialog")
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: "Escape / Back closes this test"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.close()
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back
                || event.key === Qt.Key_Backspace) {
            dialog.close()
            event.accepted = true
            return
        }
        keyCount++
        lastKey = keyName(event.key)
        lastText = event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32
                   ? event.text
                   : ""
        event.accepted = true
    }
}
