import QtQuick

Item {
    id: home

    signal requestHeaderFocus()

    function visibleRows() {
        const all = [recentRow, favoritesRow, streamingRow, appsRow]
        return all.filter(function (row) { return row.visible })
    }

    function focusFirst() {
        const rows = visibleRows()
        if (rows.length > 0)
            rows[0].focusAt(0)
    }

    function focusContent() {
        focusFirst()
    }

    function moveRow(delta, index) {
        const rows = visibleRows()
        if (rows.length === 0)
            return
        let current = -1
        for (let i = 0; i < rows.length; ++i) {
            if (rows[i].activeFocus)
                current = i
        }
        if (current < 0)
            current = 0
        const target = current + delta
        if (target < 0) {
            home.requestHeaderFocus()
            return
        }
        if (target >= rows.length)
            return
        rows[target].focusAt(index)
    }

    function currentApp() {
        const rows = visibleRows()
        for (let i = 0; i < rows.length; ++i) {
            if (rows[i].activeFocus) {
                const item = rows[i].items[rows[i].currentIndex()]
                return item ? item.id : ""
            }
        }
        return ""
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Theme.s(10)
        spacing: Theme.s(2)

        MediaRow {
            id: recentRow
            width: parent.width
            title: "Continue"
            items: catalog.recent
            onNavigate: (delta, index) => home.moveRow(delta, index)
            onActivated: index => catalog.launch(items[index].id)
        }

        MediaRow {
            id: favoritesRow
            width: parent.width
            title: "Your apps"
            items: catalog.favorites
            onNavigate: (delta, index) => home.moveRow(delta, index)
            onActivated: index => catalog.launch(items[index].id)
        }

        MediaRow {
            id: streamingRow
            width: parent.width
            title: "Streaming"
            items: catalog.streaming
            onNavigate: (delta, index) => home.moveRow(delta, index)
            onActivated: index => catalog.launch(items[index].id)
        }

        MediaRow {
            id: appsRow
            width: parent.width
            title: "Applications"
            items: catalog.nativeApps
            onNavigate: (delta, index) => home.moveRow(delta, index)
            onActivated: index => catalog.launch(items[index].id)
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.s(12)
        visible: visibleRows().length === 0
        Text {
            text: "Nothing to watch yet"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(28)
            font.weight: Font.DemiBold
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "Open Settings to connect to the network, or add a web shortcut."
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.s(17)
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Component.onCompleted: Qt.callLater(focusFirst)
}
