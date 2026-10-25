import QtQuick
import QtQuick.Controls

Item {
    id: tile
    property var app: ({})
    property bool selected: false
    property bool active: false
    property bool showBadge: true

    signal activated()
    signal detailsRequested()

    implicitWidth: Theme.s(216)
    implicitHeight: Theme.s(160)

    function activate() {
        tile.activated()
    }

    Rectangle {
        id: card
        width: parent.width
        height: Theme.s(124)
        radius: Theme.radius
        clip: true
        color: tile.app.color ? tile.app.color : Theme.surface

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(card.color, 1.18) }
            GradientStop { position: 1.0; color: Qt.darker(card.color, 1.45) }
        }

        Image {
            id: icon
            anchors.centerIn: parent
            width: Theme.s(64)
            height: Theme.s(64)
            source: tile.app.icon ? tile.app.icon : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: status === Image.Ready
            cache: true
        }

        Text {
            anchors.centerIn: parent
            visible: icon.status !== Image.Ready
            text: tile.app.short ? tile.app.short : (tile.app.name ? tile.app.name.charAt(0) : "?")
            color: "white"
            opacity: 0.94
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(46)
            font.weight: Font.DemiBold
        }

        Text {
            visible: tile.showBadge
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.s(10)
            text: tile.app.kind === "web" ? "WEB" : (tile.app.kind === "android" ? "AND" : "APP")
            color: "white"
            opacity: 0.62
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(10)
            font.letterSpacing: Theme.s(1.2)
            font.weight: Font.DemiBold
        }

        // Subtle top sheen.
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: parent.height * 0.45
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        Rectangle {
            visible: !tile.app.valid
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            Text {
                anchors.centerIn: parent
                text: "!"
                color: Theme.warn
                font.pixelSize: Theme.s(42)
                font.weight: Font.Bold
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: tile.selected && tile.active ? Theme.s(3) : Theme.s(1)
            border.color: tile.selected && tile.active ? Theme.accent
                        : (tile.selected ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.10))
        }

        Rectangle {
            visible: tile.app.favorite === true
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: Theme.s(12)
            width: Theme.s(8)
            height: Theme.s(8)
            radius: Theme.s(4)
            color: Theme.accent
        }
    }

    Text {
        anchors.top: card.bottom
        anchors.topMargin: Theme.s(8)
        width: parent.width
        text: tile.app.name ? tile.app.name : ""
        color: tile.selected && tile.active ? Theme.text : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(17)
        font.weight: tile.selected ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    scale: tile.selected && tile.active ? 1.045 : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: tile.activated()
        onPressAndHold: tile.detailsRequested()
    }
}
