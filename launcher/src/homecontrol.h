#pragma once

#include <QLocalServer>
#include <QObject>
#include <QString>

// HomeRelay listens on $XDG_RUNTIME_DIR/pivista-home.sock.
//
// The sway Home binding runs /usr/lib/pivista/home.sh, which closes foreground
// streaming/native windows and sends a message to this socket. The launcher
// then returns to the home screen even though the compositor consumed the key.
class HomeRelay : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool listening READ listening NOTIFY listeningChanged)

public:
    explicit HomeRelay(QObject *parent = nullptr);
    ~HomeRelay() override;

    bool listening() const { return m_server.isListening(); }
    QString socketPath() const { return m_path; }

signals:
    void homeRequested();
    void listeningChanged();

private slots:
    void handleConnection();

private:
    QLocalServer m_server;
    QString m_path;
};
