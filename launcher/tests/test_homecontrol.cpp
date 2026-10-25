#include "homecontrol.h"

#include <QLocalSocket>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

class HomeRelayTest : public QObject
{
    Q_OBJECT

private slots:
    void emitsHomeRequested();
};

void HomeRelayTest::emitsHomeRequested()
{
    QTemporaryDir runtime;
    QVERIFY(runtime.isValid());

    const QByteArray previous = qgetenv("XDG_RUNTIME_DIR");
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());

    HomeRelay relay;
    QVERIFY2(relay.listening(), qPrintable(relay.socketPath()));
    QVERIFY(relay.socketPath().startsWith(runtime.path()));

    QSignalSpy spy(&relay, &HomeRelay::homeRequested);
    QLocalSocket client;
    client.connectToServer(relay.socketPath());
    QVERIFY(client.waitForConnected(2000));
    QTRY_COMPARE(spy.count(), 1);
    QVERIFY(client.waitForDisconnected(2000));

    if (previous.isEmpty())
        qunsetenv("XDG_RUNTIME_DIR");
    else
        qputenv("XDG_RUNTIME_DIR", previous);
}

QTEST_MAIN(HomeRelayTest)
#include "test_homecontrol.moc"
