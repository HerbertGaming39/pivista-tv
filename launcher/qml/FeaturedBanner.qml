import QtQuick

FocusScope {
    id: banner

    property var featured: ({})
    property bool hasContent: featured && featured.id !== undefined && featured.id !== ""
    signal activated()
    signal navigateUp()
    signal navigateDown()

    implicitHeight: Theme.s(258)
    visible: hasContent
    focus: true
    activeFocusOnTab: true

    function activate() {
        if (hasContent)
            banner.activated()
    }

    onVisibleChanged: if (visible) Qt.callLater(function () { banner.forceActiveFocus() })
    Component.onCompleted: if (visible) Qt.callLater(function () { banner.forceActiveFocus() })

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Theme.s(24)
        clip: true
        color: banner.featured.color ? banner.featured.color : Theme.surfaceHigh

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.darker(surface.color, 2.15) }
            GradientStop { position: 0.52; color: Qt.darker(surface.color, 1.30) }
            GradientStop { position: 1.0; color: Qt.darker(surface.color, 2.60) }
        }

        // Large, original colour field on the right. It is deliberately
        // abstract: no provider logos or copied artwork are used here.
        Rectangle {
            width: Theme.s(420)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(-80)
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }

        Rectangle {
            width: Theme.s(250)
            height: width
            radius: Theme.s(30)
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(132)
            anchors.verticalCenter: parent.verticalCenter
            rotation: -8
            color: Qt.rgba(0, 0, 0, 0.18)
            border.width: Theme.s(1)
            border.color: Qt.rgba(1, 1, 1, 0.18)

            Text {
                anchors.centerIn: parent
                text: banner.featured.short ? banner.featured.short : ""
                color: "white"
                opacity: 0.92
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(96)
                font.weight: Font.Black
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: banner.activeFocus ? Theme.s(3) : Theme.s(1)
            border.color: banner.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: Theme.s(46)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.s(520)
            spacing: Theme.s(10)

            Row {
                spacing: Theme.s(10)
                Rectangle {
                    height: Theme.s(25)
                    width: kindText.implicitWidth + Theme.s(20)
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.28)
                    Text {
                        id: kindText
                        anchors.centerIn: parent
                        text: banner.featured.kind === "web" ? "WEB SHORTCUT" : "INSTALLED APP"
                        color: "white"
                        opacity: 0.80
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.s(10)
                        font.letterSpacing: Theme.s(1.4)
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: banner.featured.category ? banner.featured.category : "Featured"
                    color: "white"
                    opacity: 0.60
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                }
            }

            Text {
                width: parent.width
                text: banner.featured.name ? banner.featured.name : ""
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(50)
                font.weight: Font.Black
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: banner.featured.notes
                      ? banner.featured.notes
                      : (banner.featured.comment ? banner.featured.comment : "Open this application from your home screen.")
                color: "white"
                opacity: 0.78
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(15)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Rectangle {
                height: Theme.s(44)
                width: openText.implicitWidth + Theme.s(42)
                radius: height / 2
                color: banner.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.16)
                border.width: Theme.s(1)
                border.color: banner.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.28)

                Text {
                    id: openText
                    anchors.centerIn: parent
                    text: "Open  ›"
                    color: banner.activeFocus ? Theme.bg : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(15)
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    Keys.onReturnPressed: banner.activate()
    Keys.onEnterPressed: banner.activate()
    Keys.onUpPressed: banner.navigateUp()
    Keys.onDownPressed: banner.navigateDown()
    MouseArea {
        anchors.fill: parent
        onClicked: {
            banner.forceActiveFocus()
            banner.activate()
        }
    }
}
