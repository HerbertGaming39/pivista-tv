import QtQuick

Item {
    id: actionList
    property var actions: []
    property int selectedIndex: 0
    property alias currentIndex: list.currentIndex
    implicitHeight: Math.max(Theme.s(60), actions.length * Theme.s(64))

    signal triggered(int index)
    signal navigateUp()
    signal navigateDown()

    function focusFirst() {
        if (actions.length === 0)
            return false
        list.currentIndex = Math.min(selectedIndex, actions.length - 1)
        list.forceActiveFocus()
        return true
    }

    function focusAt(index) {
        if (actions.length === 0)
            return false
        list.currentIndex = Math.max(0, Math.min(index, actions.length - 1))
        list.forceActiveFocus()
        return true
    }

    ListView {
        id: list
        anchors.fill: parent
        model: actionList.actions
        focus: false
        spacing: Theme.s(8)
        clip: true
        keyNavigationWraps: false

        Keys.onReturnPressed: if (currentItem) actionList.triggered(list.currentIndex)
        Keys.onEnterPressed: if (currentItem) actionList.triggered(list.currentIndex)
        // Some TV remotes send KEY_SELECT rather than KEY_ENTER for OK.
        Keys.onPressed: function (event) {
            if ((event.key === Qt.Key_Select || event.key === Qt.Key_Space) && currentItem) {
                actionList.triggered(list.currentIndex)
                event.accepted = true
            }
        }
        Keys.onUpPressed: {
            if (list.currentIndex > 0)
                list.currentIndex--
            else
                actionList.navigateUp()
        }
        Keys.onDownPressed: {
            if (list.currentIndex < list.count - 1)
                list.currentIndex++
            else
                actionList.navigateDown()
        }

        delegate: Rectangle {
            width: list.width
            height: Theme.s(56)
            radius: Theme.s(12)
            color: ListView.isCurrentItem ? Theme.surfaceHigh : Theme.surface
            border.width: ListView.isCurrentItem ? Theme.s(2) : Theme.s(1)
            border.color: ListView.isCurrentItem ? Theme.accent : Qt.rgba(1, 1, 1, 0.06)

            Behavior on color {
                ColorAnimation { duration: Theme.animShort }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.s(18)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: ListView.isCurrentItem ? Theme.text : Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(16)
                font.weight: ListView.isCurrentItem ? Font.DemiBold : Font.Normal
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(18)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.detail !== undefined ? modelData.detail : ""
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(14)
                elide: Text.ElideRight
                width: Math.min(implicitWidth, parent.width * 0.55)
                horizontalAlignment: Text.AlignRight
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    list.currentIndex = index
                    actionList.triggered(index)
                }
            }
        }
    }
}
