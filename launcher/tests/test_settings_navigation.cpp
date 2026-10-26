// Regression test for reaching and using Settings with only remote keys.
//
// The reported failure was a Home screen where arrows only moved between the
// featured tile and the first row, so Settings could not be opened at all.
// This test drives the production QML from the banner to Settings > Input with
// the same key events a USB keyboard or D-pad remote sends.

#include "appcatalog.h"
#include "controlclient.h"
#include "homecontrol.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>

namespace {
constexpr const char *kQmlDir = PIVISTA_QML_DIR;
constexpr const char *kCatalog = PIVISTA_WEBAPP_CATALOG;

bool hasFocusWithin(QQuickItem *item)
{
    if (!item)
        return false;
    if (item->hasActiveFocus())
        return true;
    for (auto *child : item->findChildren<QQuickItem *>()) {
        if (child->hasActiveFocus())
            return true;
    }
    return false;
}
}

class SettingsNavigationTest : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void settingsAreReachableFromHomeWithRemoteKeys();
    void inputPageOpensAndReturns();

private:
    AppCatalog m_catalog;
    ControlClient m_control;
    HomeRelay m_homeRelay;
    QQmlApplicationEngine m_engine;
};

void SettingsNavigationTest::initTestCase()
{
    const QString qmlDir = qEnvironmentVariable("PIVISTA_QML_DIR",
                                                QString::fromUtf8(kQmlDir));
    m_engine.rootContext()->setContextProperty(QStringLiteral("catalog"), &m_catalog);
    m_engine.rootContext()->setContextProperty(QStringLiteral("control"), &m_control);
    m_engine.rootContext()->setContextProperty(QStringLiteral("homeRelay"), &m_homeRelay);
    m_engine.rootContext()->setContextProperty(QStringLiteral("windowedMode"), true);
    m_engine.rootContext()->setContextProperty(QStringLiteral("qmlDirectory"), qmlDir);
    m_engine.rootContext()->setContextProperty(QStringLiteral("uiDevMode"), true);
    m_engine.rootContext()->setContextProperty(QStringLiteral("screenshotPath"), QString());
    m_engine.rootContext()->setContextProperty(QStringLiteral("initialScreen"),
                                               QStringLiteral("home"));
    m_engine.rootContext()->setContextProperty(QStringLiteral("uiWizardStep"), 0);
    m_engine.rootContext()->setContextProperty(QStringLiteral("initialSettingsPage"), QString());
    m_engine.rootContext()->setContextProperty(QStringLiteral("initialDetails"), QString());
    m_engine.rootContext()->setContextProperty(QStringLiteral("initialWidth"), 1280);
    m_engine.rootContext()->setContextProperty(QStringLiteral("initialHeight"), 720);

    m_engine.load(QUrl::fromLocalFile(qmlDir + QStringLiteral("/Main.qml")));
    QVERIFY2(!m_engine.rootObjects().isEmpty(), "Main.qml did not load");
}

void SettingsNavigationTest::settingsAreReachableFromHomeWithRemoteKeys()
{
    auto *window = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    QVERIFY(window);
    QTRY_VERIFY(window->isVisible());

    auto *nav = window->findChild<QQuickItem *>(QStringLiteral("navList"));
    QVERIFY(nav);
    QTRY_COMPARE(nav->property("currentIndex").toInt(), 0);

    // The featured banner owns initial focus. Up must reach the header; this
    // is the path that previously trapped a remote on the content.
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(window->findChild<QQuickItem *>(
                                  QStringLiteral("featuredBanner"))), 5000);
    QTest::keyClick(window, Qt::Key_Up);
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(nav), 2000);

    // Home -> Apps -> Games -> Media -> Search -> Settings.
    for (int i = 0; i < 5; ++i)
        QTest::keyClick(window, Qt::Key_Right);
    QTRY_COMPARE(nav->property("currentIndex").toInt(), 5);

    // Enter opens the highlighted section (Down only moves focus inside the
    // currently loaded screen).
    QTest::keyClick(window, Qt::Key_Return);
    auto *settings = window->findChild<QQuickItem *>(QStringLiteral("settingsScreen"));
    QTRY_VERIFY_WITH_TIMEOUT(settings != nullptr, 3000);
    auto *sections = window->findChild<QQuickItem *>(QStringLiteral("settingsSections"));
    QTRY_VERIFY_WITH_TIMEOUT(sections != nullptr, 3000);
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(sections), 3000);

    // Enter opens the first section. It must not bounce back to the header or
    // leave focus on a page with no action list.
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_COMPARE(settings->property("page").toString(), QStringLiteral("network"));
    auto *netActions = settings->findChild<QQuickItem *>(QStringLiteral("netActions"));
    QVERIFY(netActions);
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(netActions), 3000);

    // Back returns to the section list rather than all the way Home.
    QTest::keyClick(window, Qt::Key_Escape);
    QTRY_COMPARE(settings->property("page").toString(), QString());
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(sections), 3000);
}

void SettingsNavigationTest::inputPageOpensAndReturns()
{
    auto *window = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    QVERIFY(window);
    auto *settings = window->findChild<QQuickItem *>(QStringLiteral("settingsScreen"));
    QVERIFY(settings);
    auto *sections = window->findChild<QQuickItem *>(QStringLiteral("settingsSections"));
    QVERIFY(sections);
    QTRY_VERIFY(hasFocusWithin(sections));

    // Network, Time and date, Remote support, Display, Input.
    sections->setProperty("currentIndex", 4);
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_COMPARE(settings->property("page").toString(), QStringLiteral("input"));

    auto *actions = settings->findChild<QQuickItem *>(QStringLiteral("settingsInputActions"));
    QVERIFY(actions);
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(actions), 3000);

    // The first row opens the key probe. It is local UI, so it must work even
    // when the control service is unavailable in this test.
    QTest::keyClick(window, Qt::Key_Return);
    auto *probe = settings->findChild<QQuickItem *>(QStringLiteral("inputTestDialog"));
    QVERIFY(probe);
    QTRY_VERIFY_WITH_TIMEOUT(probe->isVisible(), 2000);

    QTest::keyClick(window, Qt::Key_Down);
    QTRY_VERIFY(probe->property("keyCount").toInt() >= 1);
    QTest::keyClick(window, Qt::Key_Escape);
    QTRY_VERIFY(!probe->isVisible());
    QTRY_VERIFY_WITH_TIMEOUT(hasFocusWithin(actions), 3000);
}

int main(int argc, char *argv[])
{
    QTemporaryDir config;
    if (!config.isValid())
        return 2;
    qputenv("XDG_CONFIG_HOME", (config.path() + QStringLiteral("/config")).toUtf8());
    qputenv("XDG_RUNTIME_DIR", (config.path() + QStringLiteral("/run")).toUtf8());
    qputenv("PIVISTA_APPLICATION_DIRS", (config.path() + QStringLiteral("/apps")).toUtf8());
    qputenv("PIVISTA_WEBAPP_CATALOG", QByteArray(kCatalog));
    qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("QT_QUICK_BACKEND", "software");

    QCoreApplication::setOrganizationName(QStringLiteral("PiVistaTest"));
    QCoreApplication::setApplicationName(QStringLiteral("SettingsNavigationTest"));

    QGuiApplication app(argc, argv);
    SettingsNavigationTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_settings_navigation.moc"
