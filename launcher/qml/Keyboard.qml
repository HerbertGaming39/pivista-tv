import QtQuick

Item {
    id: keyboard
    property string text: ""
    property bool shift: false
    property bool symbols: false
    property var keys: buildKeys()

    signal accepted()
    signal cancelled()

    implicitHeight: Theme.s(332)

    function buildKeys() {
        if (symbols) {
            return [
                "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
                "@", "#", "$", "%", "&", "*", "-", "_", "+", "=",
                "!", "?", ":", ";", "'", "\"", "(", ")", "/", "\\",
                "abc", "space", ".", ",", "⌫", "Done"
            ]
        }
        const top = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        const middle = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
        const bottom = ["z", "x", "c", "v", "b", "n", "m"]
        const cased = function (letters) {
            return letters.map(function (letter) { return shift ? letter.toUpperCase() : letter })
        }
        return cased(top)
            .concat(cased(middle))
            .concat(["⇧"])
            .concat(cased(bottom))
            .concat(["⌫", "123", "space", "@", ".", "-", "Done"])
    }

    function press(key) {
        if (key === "⌫") {
            keyboard.text = keyboard.text.slice(0, -1)
        } else if (key === "space") {
            keyboard.text += " "
        } else if (key === "⇧") {
            keyboard.shift = !keyboard.shift
            keyboard.keys = keyboard.buildKeys()
        } else if (key === "123") {
            keyboard.symbols = true
            keyboard.keys = keyboard.buildKeys()
        } else if (key === "abc") {
            keyboard.symbols = false
            keyboard.keys = keyboard.buildKeys()
        } else if (key === "Done") {
            keyboard.accepted()
        } else {
            keyboard.text += key
            if (keyboard.shift && !keyboard.symbols) {
                keyboard.shift = false
                keyboard.keys = keyboard.buildKeys()
            }
        }
    }

    function focusKeyboard() {
        grid.forceActiveFocus()
    }

    GridView {
        id: grid
        anchors.fill: parent
        cellWidth: width / 10
        cellHeight: Theme.s(58)
        model: keyboard.keys
        clip: true
        focus: true
        keyNavigationWraps: false

        Keys.onReturnPressed: keyboard.press(keyboard.keys[grid.currentIndex])
        Keys.onEnterPressed: keyboard.press(keyboard.keys[grid.currentIndex])
        Keys.onEscapePressed: keyboard.cancelled()
        Keys.onPressed: function (event) {
            // A USB/Bluetooth keyboard should type directly into the dialog,
            // not force the user to navigate the on-screen keys one by one.
            if (event.key === Qt.Key_Backspace) {
                keyboard.text = keyboard.text.slice(0, -1)
                event.accepted = true
            } else if (event.text.length === 1
                       && event.text.charCodeAt(0) >= 0x20
                       && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                keyboard.text += event.text
                event.accepted = true
            }
        }

        delegate: Rectangle {
            width: grid.cellWidth - Theme.s(8)
            height: grid.cellHeight - Theme.s(8)
            radius: Theme.s(10)
            color: GridView.isCurrentItem ? Theme.accent
                 : (mouse.containsMouse ? Theme.surfaceHigh : Theme.surface)
            border.width: GridView.isCurrentItem ? 0 : Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.08)

            Behavior on color {
                ColorAnimation { duration: Theme.animShort }
            }

            Text {
                anchors.centerIn: parent
                text: modelData
                color: GridView.isCurrentItem ? Theme.bg : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: modelData === "Done" ? Theme.s(15) : Theme.s(20)
                font.weight: GridView.isCurrentItem ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    grid.currentIndex = index
                    keyboard.press(modelData)
                }
            }
        }
    }
}
