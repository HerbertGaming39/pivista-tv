import QtQuick

Item {
    id: media

    signal requestHeaderFocus()

    function visibleRows() {
        return [recentRow, streamingRow, installedRow].filter(function (row) { return row.visible })
    }

    function focusFirst() {
        const rows = visibleRows()
        if (rows.length > 0) {
            rows[0].focusAt(0)
            // Entering the section always starts at the top. Row geometry is
            // not reliable while the Loader is still laying out, so scrolling
            // here can push the heading and the first row off-screen.
            flick.contentY = 0
        } else {
            media.requestHeaderFocus()
        }
    }

    function focusContent() {
        focusFirst()
    }

    function moveRow(delta, index) {
        const rows = visibleRows()
        if (rows.length === 0) {
            media.requestHeaderFocus()
            return
        }
        let current = -1
        for (let i = 0; i < rows.length; ++i) {
            if (rows[i].activeFocus)
                current = i
        }
        if (current < 0)
            current = 0
        const target = current + delta
        if (target < 0) {
            media.requestHeaderFocus()
            return
        }
        if (target >= rows.length)
            return
        rows[target].focusAt(index)
        media.ensureVisible(rows[target])
    }

    function ensureVisible(item) {
        if (!item)
            return
        const top = item.mapToItem(column, 0, 0).y
        const bottom = top + item.height
        // A Loader can deliver focus before its content has been laid out.
        // Ignore geometry that is outside the column instead of scrolling the
        // whole section off-screen.
        if (top < 0 || bottom > column.height + 1)
            return
        const limit = Math.max(0, flick.contentHeight - flick.height)
        if (top < flick.contentY)
            flick.contentY = Math.max(0, Math.min(top - Theme.s(18), limit))
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.max(0, Math.min(bottom - flick.height + Theme.s(18), limit))
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, column.implicitHeight)
        boundsBehavior: Flickable.StopAtBounds
        interactive: false

        Behavior on contentY {
            NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic }
        }

        Column {
            id: column
            width: flick.width
            spacing: Theme.s(2)

            Text {
                text: "Media"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(30)
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                text: "Streaming shortcuts and installed media applications. Local USB libraries appear when a compatible player provides them."
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.s(13)
                wrapMode: Text.WordWrap
                bottomPadding: Theme.s(8)
            }

            MediaRow {
                id: recentRow
                width: parent.width
                title: "Recently opened"
                items: catalog.recent
                visible: items.length > 0
                onNavigate: (delta, index) => media.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: media.ensureVisible(this)
            }

            MediaRow {
                id: streamingRow
                width: parent.width
                title: "Streaming services"
                items: catalog.streaming
                visible: items.length > 0
                onNavigate: (delta, index) => media.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: media.ensureVisible(this)
            }

            MediaRow {
                id: installedRow
                width: parent.width
                title: "Installed media apps"
                items: catalog.mediaApps
                visible: items.length > 0
                onNavigate: (delta, index) => media.moveRow(delta, index)
                onActivated: index => catalog.launch(items[index].id)
                onFocused: media.ensureVisible(this)
            }

            Rectangle {
                width: parent.width
                height: Theme.s(92)
                radius: Theme.s(14)
                color: Theme.surface
                border.width: Theme.s(1)
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Text {
                    anchors.fill: parent
                    anchors.margins: Theme.s(18)
                    text: catalog.mediaApps.length === 0
                          ? "No installed media application was found. PiVista does not bundle a player. Install Kodi, Jellyfin Media Player or a similar package, or use a streaming shortcut above."
                          : "Local files and network libraries are provided by the installed player. PiVista does not index or copy your media."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.s(12)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Component.onCompleted: Qt.callLater(focusFirst)
}
