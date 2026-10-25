import QtQuick

Item {
    id: saver
    anchors.fill: parent
    visible: false
    z: 30
    focus: visible

    signal dismissed()

    Keys.onPressed: function (event) {
        saver.dismissed()
        event.accepted = true
    }

    property string clockText: Qt.formatTime(new Date(), "HH:mm")
    property string dateText: Qt.formatDateTime(new Date(), "dddd, d MMMM")

    Timer {
        interval: 1000
        repeat: true
        running: saver.visible
        onTriggered: {
            saver.clockText = Qt.formatTime(new Date(), "HH:mm")
            saver.dateText = Qt.formatDateTime(new Date(), "dddd, d MMMM")
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bgDeep

        Rectangle {
            id: glowA
            width: Theme.s(900)
            height: width
            radius: width / 2
            color: Qt.rgba(0.43, 0.91, 0.98, 0.055)
            x: -Theme.s(220)
            y: -Theme.s(300)

            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { to: Theme.s(60); duration: 26000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -Theme.s(220); duration: 26000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            width: Theme.s(760)
            height: width
            radius: width / 2
            color: Qt.rgba(0.65, 0.55, 0.98, 0.05)
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -Theme.s(180)
            anchors.bottomMargin: -Theme.s(240)
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.s(10)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: saver.clockText
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(150)
            font.weight: Font.Thin
            font.letterSpacing: Theme.s(-4)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: saver.dateText
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(24)
            font.capitalization: Font.Capitalize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Theme.s(30)
            text: "Press any key to return"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(14)
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: saver.dismissed()
    }
}
