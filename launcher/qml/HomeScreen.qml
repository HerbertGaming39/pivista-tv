import QtQuick

Item {
    id: home
    objectName: "homeScreen"

    signal requestHeaderFocus()

    function visibleRows() {
        const all = [recentRow, favoritesRow, streamingRow, appsRow]
        return all.filter(function (row) { return row.visible })
    }

    function activeRow() {
        const rows = visibleRows()
        for (let i = 0; i < rows.length; ++i) {
            if (rows[i].activeFocus)
                return rows[i]
        }
        return null
    }

    function focusFirst() {
        if (banner.visible)
            banner.forceActiveFocus()
        else if (visibleRows().length > 0)
            focusFirstRow()
        else
            // An empty Home still has to be navigable: otherwise there is no
            // focus target at all and the remote cannot reach Settings to add
            // a shortcut or connect the network.
            home.requestHeaderFocus()
    }

    function focusContent() {
        focusFirst()
    }

    function focusFirstRow() {
        const rows = visibleRows()
        if (rows.length > 0) {
            rows[0].focusAt(0)
            ensureVisible(rows[0])
        }
    }

    function ensureVisible(item) {
        if (!item || !flick.contentItem)
            return
        const top = item.mapToItem(column, 0, 0).y
        const bottom = top + item.height
        const margin = Theme.s(18)
        if (top < flick.contentY)
            flick.contentY = Math.max(0, top - margin)
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height,
                                                  bottom - flick.height + margin))
    }

    function moveRow(delta, index) {
        const rows = visibleRows()
        if (rows.length === 0) {
            if (banner.visible && delta < 0)
                banner.forceActiveFocus()
            return
        }
        const current = activeRow()
        if (current === null) {
            if (delta > 0)
                focusFirstRow()
            else if (banner.visible)
                banner.forceActiveFocus()
            return
        }
        const currentIndex = rows.indexOf(current)
        const target = currentIndex + delta
        if (target < 0) {
            if (banner.visible)
                banner.forceActiveFocus()
            else
                home.requestHeaderFocus()
            return
        }
        if (target >= rows.length)
            return
        rows[target].focusAt(index)
        ensureVisible(rows[target])
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: false

        Behavior on contentY {
            NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
        }

        Column {
            id: column
            width: flick.width
            spacing: Theme.s(2)

            FeaturedBanner {
                id: banner
                objectName: "featuredBanner"
                width: parent.width
                featured: catalog.featured
                onActivated: catalog.launch(featured.id)
                onNavigateDown: home.focusFirstRow()
                // Up from the featured banner is the only way back to the
                // header on a home screen whose first row is already the top
                // of the content.  Without it a remote is trapped between the
                // banner and the first row and cannot reach Settings.
                onNavigateUp: home.requestHeaderFocus()
            }

            MediaRow {
                id: recentRow
                objectName: "recentRow"
                width: parent.width
                title: "Recently opened"
                items: catalog.recent
                visible: AppSettings.showRecent && items.length > 0
                onNavigate: (delta, index) => home.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: home.ensureVisible(this)
            }

            MediaRow {
                id: favoritesRow
                objectName: "favoritesRow"
                width: parent.width
                title: "Your apps"
                items: catalog.favorites
                visible: AppSettings.showFavorites && items.length > 0
                onNavigate: (delta, index) => home.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: home.ensureVisible(this)
            }

            MediaRow {
                id: streamingRow
                objectName: "streamingRow"
                width: parent.width
                title: "Streaming"
                items: catalog.streaming
                visible: AppSettings.showStreaming && items.length > 0
                onNavigate: (delta, index) => home.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: home.ensureVisible(this)
            }

            MediaRow {
                id: appsRow
                objectName: "appsRow"
                width: parent.width
                title: "Installed applications"
                items: catalog.nativeApps
                visible: AppSettings.showApps && items.length > 0
                onNavigate: (delta, index) => home.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: home.ensureVisible(this)
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.s(12)
        visible: !banner.visible && visibleRows().length === 0
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

    Connections {
        target: catalog
        function onChanged() {
            if (!banner.activeFocus && home.activeRow() === null)
                Qt.callLater(home.focusFirst)
        }
    }

    Timer {
        interval: 120
        repeat: false
        running: true
        onTriggered: if (!banner.activeFocus && home.activeRow() === null) home.focusFirst()
    }

    Component.onCompleted: Qt.callLater(focusFirst)
}
