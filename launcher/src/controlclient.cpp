#include "controlclient.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

ControlClient::ControlClient(QObject *parent)
    : QObject(parent)
{
    m_path = qEnvironmentVariable("PIVISTA_CONTROL_SOCKET",
                                  QStringLiteral("/run/pivista/control.sock"));
    m_socket = new QLocalSocket(this);
    connect(m_socket, &QLocalSocket::connected, this, [this] {
        m_buffer.clear();
        emit connectedChanged();
    });
    connect(m_socket, &QLocalSocket::disconnected, this, [this] {
        emit connectedChanged();
        scheduleReconnect();
    });
    connect(m_socket, &QLocalSocket::readyRead, this, &ControlClient::onReadyRead);
    connect(m_socket, &QLocalSocket::errorOccurred, this, &ControlClient::onSocketError);
    connectToService();
}

bool ControlClient::connected() const
{
    return m_socket && m_socket->state() == QLocalSocket::ConnectedState;
}

void ControlClient::connectToService()
{
    if (connected())
        return;
    m_socket->abort();
    m_socket->connectToServer(m_path);
}

void ControlClient::scheduleReconnect()
{
    QTimer::singleShot(2000, this, [this] { connectToService(); });
}

void ControlClient::onSocketError(QLocalSocket::LocalSocketError error)
{
    Q_UNUSED(error)
    emit connectedChanged();
    scheduleReconnect();
}

int ControlClient::call(const QString &action, const QVariantMap &params, int timeoutMs)
{
    const int id = m_nextId++;
    if (!connected()) {
        QTimer::singleShot(0, this, [this, id] {
            emit failed(id, QStringLiteral("service_unavailable"),
                        tr("The PiVista control service is not running."));
        });
        return id;
    }
    QJsonObject request;
    request.insert(QStringLiteral("id"), id);
    request.insert(QStringLiteral("action"), action);
    request.insert(QStringLiteral("params"), QJsonObject::fromVariantMap(params));
    m_socket->write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    m_socket->flush();

    auto *timer = new QTimer(this);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, this, [this, id, timer, action] {
        m_timeouts.remove(id);
        timer->deleteLater();
        emit failed(id, QStringLiteral("timeout"),
                    tr("%1 did not respond in time.").arg(action));
    });
    m_timeouts.insert(id, timer);
    timer->start(timeoutMs);
    return id;
}

void ControlClient::onReadyRead()
{
    m_buffer += m_socket->readAll();
    if (m_buffer.size() > 4 * 1024 * 1024) {
        m_buffer.clear();
        m_socket->abort();
        return;
    }
    int newline;
    while ((newline = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);
        if (line.trimmed().isEmpty())
            continue;
        QJsonParseError error{};
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            qWarning() << "pivistad: malformed response";
            continue;
        }
        const QJsonObject object = document.object();
        const int id = object.value(QStringLiteral("id")).toInt(-1);
        if (QTimer *timer = m_timeouts.take(id)) {
            timer->stop();
            timer->deleteLater();
        }
        if (object.value(QStringLiteral("ok")).toBool()) {
            emit response(id, object.value(QStringLiteral("data")).toObject().toVariantMap());
        } else {
            const QJsonObject failure = object.value(QStringLiteral("error")).toObject();
            emit failed(id,
                        failure.value(QStringLiteral("code")).toString(QStringLiteral("unknown")),
                        failure.value(QStringLiteral("message")).toString(tr("The action failed.")));
        }
    }
}
