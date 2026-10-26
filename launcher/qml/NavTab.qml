import QtQuick

Item {
    id: tab
    property string label: ""
    property bool selected: false
    property bool tabFocused: false

    implicitWidth: text.implicitWidth + Theme.s(36)
    implicitHeight: Theme.s(44)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: tab.selected ? Qt.rgba(0.43, 0.91, 0.98, 0.14)
                            : (tab.tabFocused ? Theme.surface : "transparent")
        border.width: tab.tabFocused ? Theme.s(2) : 0
        border.color: Theme.accent

        Behavior on color {
            ColorAnimation { duration: Theme.animShort }
        }
        Behavior on border.width {
            NumberAnimation { duration: Theme.animShort; easing.type: Easing.OutCubic }
        }

        // A tiny lift on focus reads at sofa distance without moving the row.
        scale: tab.tabFocused ? 1.04 : 1.0
        Behavior on scale {
            NumberAnimation { duration: Theme.animShort; easing.type: Easing.OutCubic }
        }
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: tab.label
        color: tab.selected ? Theme.accent : (tab.tabFocused ? Theme.text : Theme.textDim)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(16)
        font.weight: tab.selected ? Font.DemiBold : Font.Normal
    }

    MouseArea {
        anchors.fill: parent
        onClicked: tab.clicked()
    }

    signal clicked()
}
