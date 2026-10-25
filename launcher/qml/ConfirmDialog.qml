import QtQuick

FocusScope {
    id: dialog
    anchors.fill: parent
    visible: false
    z: 60

    property string title: "Are you sure?"
    property string message: ""
    property string confirmLabel: "Confirm"
    property bool danger: false

    signal confirmed()
    signal cancelled()

    function open() {
        visible = true
        Qt.callLater(function () { cancelButton.forceActiveFocus() })
    }

    function close() {
        visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.02, 0.05, 0.82)

        MouseArea {
            anchors.fill: parent
            onClicked: dialog.cancelled()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.s(640)
            height: dialogText.implicitHeight + Theme.s(190)
            radius: Theme.s(22)
            color: Theme.bgRaised
            border.width: Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Column {
                anchors.fill: parent
                anchors.margins: Theme.s(28)
                spacing: Theme.s(16)

                Text {
                    text: dialog.title
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(24)
                    font.weight: Font.DemiBold
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Text {
                    id: dialogText
                    text: dialog.message
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(16)
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Item {
                    width: parent.width
                    height: Theme.s(50)

                    Row {
                        spacing: Theme.s(14)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            id: cancelButton
                            width: Theme.s(150)
                            height: Theme.s(50)
                            radius: Theme.s(12)
                            color: activeFocus ? Theme.surfaceHigh : Theme.surface
                            border.width: activeFocus ? Theme.s(2) : Theme.s(1)
                            border.color: activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.s(16)
                            }

                            Keys.onReturnPressed: dialog.cancelled()
                            Keys.onRightPressed: confirmButton.forceActiveFocus()
                            MouseArea {
                                anchors.fill: parent
                                onClicked: dialog.cancelled()
                            }
                        }

                        Rectangle {
                            id: confirmButton
                            width: Theme.s(180)
                            height: Theme.s(50)
                            radius: Theme.s(12)
                            color: dialog.danger ? Theme.danger : Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: dialog.confirmLabel
                                color: Theme.bg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.s(16)
                                font.weight: Font.DemiBold
                            }

                            Keys.onReturnPressed: dialog.confirmed()
                            Keys.onLeftPressed: cancelButton.forceActiveFocus()
                            MouseArea {
                                anchors.fill: parent
                                onClicked: dialog.confirmed()
                            }
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: dialog.cancelled()
}
