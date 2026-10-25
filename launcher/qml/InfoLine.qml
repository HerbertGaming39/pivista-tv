import QtQuick

Item {
    id: line
    property string label: ""
    property string value: ""
    implicitHeight: Theme.s(46)

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: line.label
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(15)
    }

    Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.62
        text: line.value
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(15)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }
}
