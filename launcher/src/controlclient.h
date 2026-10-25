#pragma once

#include <QByteArray>
#include <QHash>
#include <QLocalSocket>
#include <QObject>
#include <QVariantMap>

class QTimer;

class ControlClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString socketPath READ socketPath CONSTANT)

public:
    explicit ControlClient(QObject *parent = nullptr);

    bool connected() const;
    QString socketPath() const { return m_path; }

    Q_INVOKABLE int call(const QString &action, const QVariantMap &params = {},
                         int timeoutMs = 60000);

signals:
    void connectedChanged();
    void response(int id, const QVariantMap &data);
    void failed(int id, const QString &code, const QString &message);

private:
    void connectToService();
    void onReadyRead();
    void onSocketError(QLocalSocket::LocalSocketError error);
    void scheduleReconnect();

    QLocalSocket *m_socket = nullptr;
    QByteArray m_buffer;
    QString m_path;
    int m_nextId = 1;
    QHash<int, QTimer *> m_timeouts;
};
