#include "homecontrol.h"

#include <QDebug>
#include <QDir>
#include <QLocalSocket>
#include <QStandardPaths>

HomeRelay::HomeRelay(QObject *parent)
    : QObject(parent)
{
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    QDir().mkpath(runtime);

    m_path = runtime + QStringLiteral("/pivista-home.sock");
    QLocalServer::removeServer(m_path);
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    connect(&m_server, &QLocalServer::newConnection, this, &HomeRelay::handleConnection);

    if (!m_server.listen(m_path)) {
        qWarning() << "pivista-launcher: cannot listen on" << m_path
                   << m_server.errorString();
    } else {
        qInfo() << "pivista-launcher: home channel on" << m_path;
    }
    emit listeningChanged();
}

HomeRelay::~HomeRelay()
{
    m_server.close();
    QLocalServer::removeServer(m_path);
}

void HomeRelay::handleConnection()
{
    while (QLocalSocket *socket = m_server.nextPendingConnection()) {
        socket->disconnectFromServer();
        socket->deleteLater();
        emit homeRequested();
    }
}
