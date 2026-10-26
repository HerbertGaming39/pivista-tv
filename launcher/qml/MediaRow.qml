import QtQuick

Item {
    id: row
    property string title: ""
    property var items: []
    property int currentIndexHint: 0
    // The row itself is an Item; focus lives on its horizontal ListView.
    // Vertical navigation must test that child, not row.activeFocus.
    readonly property bool rowActiveFocus: list.activeFocus

    signal navigate(int delta, int index)
    signal activated(int index)
    signal focused()

    implicitHeight: Theme.s(214)
    visible: items.length > 0

    function focusAt(index) {
        if (!visible || list.count === 0)
            return false
        list.currentIndex = Math.max(0, Math.min(index, list.count - 1))
        list.forceActiveFocus()
        return true
    }

    function currentIndex() {
        return list.currentIndex
    }

    Text {
        id: heading
        anchors.left: parent.left
        anchors.top: parent.top
        text: row.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.s(21)
        font.weight: Font.DemiBold
        opacity: 0.92
    }

    ListView {
        id: list
        anchors.top: heading.bottom
        anchors.topMargin: Theme.s(12)
        width: parent.width
        height: Theme.s(162)
        orientation: ListView.Horizontal
        spacing: Theme.s(18)
        clip: true
        model: row.items
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        keyNavigationWraps: false
        focus: false

        onActiveFocusChanged: if (activeFocus) row.focused()

        Keys.onUpPressed: row.navigate(-1, list.currentIndex)
        Keys.onDownPressed: row.navigate(1, list.currentIndex)
        Keys.onReturnPressed: if (currentItem) currentItem.activate()
        Keys.onEnterPressed: if (currentItem) currentItem.activate()

        delegate: Tile {
            app: modelData
            selected: ListView.isCurrentItem
            active: list.activeFocus
            onActivated: {
                list.currentIndex = index
                row.activated(index)
            }
        }

        Behavior on contentX {
            NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
        }
    }
}
