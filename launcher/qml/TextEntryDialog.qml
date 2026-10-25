import QtQuick

FocusScope {
    id: dialog
    anchors.fill: parent
    visible: false
    z: 50

    property string title: "Enter text"
    property string hint: ""
    property bool mask: false
    property bool busy: false
    property string errorText: ""

    signal accepted(string text)
    signal cancelled()

    function open() {
        keyboard.text = ""
        errorText = ""
        busy = false
        visible = true
        Qt.callLater(function () { keyboard.focusKeyboard() })
    }

    function close() {
        visible = false
    }

    function fail(message) {
        busy = false
        errorText = message
        keyboard.focusKeyboard()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.02, 0.05, 0.82)
    }

    Rectangle {
        anchors.centerIn: parent
        width: Theme.s(900)
        height: Theme.s(590)
        radius: Theme.s(24)
        color: Theme.bgRaised ? Theme.bgRaised : Theme.surface
        border.width: Theme.s(1)
        border.color: Qt.rgba(1, 1, 1, 0.10)

        Column {
            anchors.fill: parent
            anchors.margins: Theme.s(28)
            spacing: Theme.s(12)

            Text {
                text: dialog.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(26)
                font.weight: Font.DemiBold
            }

            Text {
                text: dialog.hint
                visible: text.length > 0
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(15)
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: Theme.s(54)
                radius: Theme.s(10)
                color: Theme.bgDeep
                border.width: Theme.s(1)
                border.color: dialog.errorText.length > 0 ? Theme.danger : Theme.accentDim

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s(16)
                    anchors.rightMargin: Theme.s(16)
                    verticalAlignment: Text.AlignVCenter
                    text: dialog.mask ? "•".repeat(keyboard.text.length) : keyboard.text
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(20)
                    elide: Text.ElideLeft
                }
            }

            Text {
                text: dialog.errorText
                visible: text.length > 0
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Keyboard {
                id: keyboard
                width: parent.width
                onAccepted: dialog.accepted(keyboard.text)
            }

            Text {
                text: "Backspace deletes · Shift changes case · Done confirms"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(12)
            }
        }
    }

    Keys.onEscapePressed: dialog.cancelled()
}
