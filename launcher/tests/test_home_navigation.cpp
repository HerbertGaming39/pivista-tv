// Regression test for remote navigation on the home screen.
//
// The featured banner is the default focus target.  If Up from the banner does
// not reach the header, a remote is trapped between the banner and the first
// content row and cannot open Settings, Apps or any other section.  This test
// loads the production QML and drives it with the same key events a USB
// keyboard or D-pad remote produces.

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

QString focusedRowName(QQuickItem *home)
{
    const QStringList names = {
        QStringLiteral("recentRow"), QStringLiteral("favoritesRow"),
        QStringLiteral("streamingRow"), QStringLiteral("appsRow")
    };
    for (const QString &name : names) {
        auto *row = home->findChild<QQuickItem *>(name);
        if (!row || !row->isVisible())
            continue;
        for (auto *child : row->findChildren<QQuickItem *>()) {
            if (child->hasActiveFocus())
                return name;
        }
    }
    return {};
}
}

class HomeNavigationTest : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void bannerCanReturnToHeaderAndSettings();
    void categoryChipsAreKeyboardReachable();

private:
    // The engine must be destroyed before the context objects it points at.
    AppCatalog m_catalog;
    ControlClient m_control;
    HomeRelay m_homeRelay;
    QQmlApplicationEngine m_engine;
};

void HomeNavigationTest::initTestCase()
{
    const QString qmlDir = qEnvironmentVariable("PIVISTA_QML_DIR",
                                                QString::fromUtf8(kQmlDir));
    m_engine.rootContext()->setContextProperty(QStringLiteral("catalog"), &m_catalog);
    m_engine.rootContext()->setContextProperty(QStringLiteral("control"), &m_control);
    m_engine.rootContext()->setContextProperty(QStringLiteral("homeRelay"), &m_homeRelay);
    m_engine.rootContext()->setContextProperty(QStringLiteral("windowedMode"), true);
    m_engine.rootContext()->setContextProperty(QStringLiteral("qmlDirectory"), qmlDir);
    // UI development mode hides the first-boot wizard so the test starts on the
    // home screen without writing setupComplete to a real user's settings.
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

void HomeNavigationTest::bannerCanReturnToHeaderAndSettings()
{
    auto *window = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    QVERIFY(window);
    QTRY_VERIFY(window->isVisible());

    auto *banner = window->findChild<QQuickItem *>(QStringLiteral("featuredBanner"));
    auto *nav = window->findChild<QQuickItem *>(QStringLiteral("navList"));
    auto *home = window->findChild<QQuickItem *>(QStringLiteral("homeScreen"));
    QVERIFY2(banner, "featured banner was not found");
    QVERIFY2(nav, "header navigation was not found");
    QVERIFY2(home, "home screen was not found");

    // Home starts on the featured banner.
    QTRY_VERIFY2(banner->hasActiveFocus(), "home did not start on the featured banner");

    // Down enters the first visible content row.
    QTest::keyClick(window, Qt::Key_Down);
    QTRY_VERIFY2(!banner->hasActiveFocus(), "Down did not leave the featured banner");

    const QString firstRow = focusedRowName(home);
    QVERIFY2(!firstRow.isEmpty(), "Down did not move focus into a content row");

    // A second Down must reach the next row.  MediaRow focus lives on its
    // child ListView, so testing row.activeFocus silently failed and reset to
    // the first row every time; Streaming could not be reached below it.
    QTest::keyClick(window, Qt::Key_Down);
    QTRY_VERIFY2(!focusedRowName(home).isEmpty(),
                 "Down left focus outside the content rows");
    const QString secondRow = focusedRowName(home);
    QVERIFY2(secondRow != firstRow,
             "Down stayed on the same row instead of reaching the next one");

    QTest::keyClick(window, Qt::Key_Up);
    QTRY_COMPARE(focusedRowName(home), firstRow);

    // Up returns to the banner, then to the header.  This second step is the
    // regression: the banner used to have no Up handler.
    QTest::keyClick(window, Qt::Key_Up);
    QTRY_VERIFY2(banner->hasActiveFocus(), "Up did not return to the featured banner");

    QTest::keyClick(window, Qt::Key_Up);
    QTRY_VERIFY2(nav->hasActiveFocus(),
                 "Up from the featured banner did not reach the header");

    // From the header the whole interface is reachable.  Right moves through
    // Home, Apps, Games, Media, Search and Settings; Enter opens Settings.
    QCOMPARE(nav->property("currentIndex").toInt(), 0);
    for (int i = 0; i < 5; ++i)
        QTest::keyClick(window, Qt::Key_Right);
    QTRY_COMPARE(nav->property("currentIndex").toInt(), 5);
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_COMPARE(window->property("view").toString(), QStringLiteral("settings"));

    // The header must not be a one-way trap either: Down returns to content.
    QTest::keyClick(window, Qt::Key_Up);
    QTRY_VERIFY(nav->hasActiveFocus());
    QTest::keyClick(window, Qt::Key_Down);
    QTRY_VERIFY(!nav->hasActiveFocus());
}

void HomeNavigationTest::categoryChipsAreKeyboardReachable()
{
    auto *window = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    QVERIFY(window);

    window->setProperty("view", QStringLiteral("apps"));
    auto *apps = window->findChild<QQuickItem *>(QStringLiteral("appsScreen"));
    auto *chips = window->findChild<QQuickItem *>(QStringLiteral("categoryChips"));
    auto *grid = window->findChild<QQuickItem *>(QStringLiteral("appsGrid"));
    QTRY_VERIFY(apps != nullptr);
    QTRY_VERIFY(chips != nullptr);
    QTRY_VERIFY(grid != nullptr);
    QTRY_VERIFY(grid->hasActiveFocus());

    // Up from the first grid row enters the category chips.
    QTest::keyClick(window, Qt::Key_Up);
    QTRY_VERIFY2(chips->hasActiveFocus(), "Up did not focus the category chips");
    QCOMPARE(chips->property("currentIndex").toInt(), 0);

    // All -> Installed -> Web; Enter filters to streaming shortcuts.
    QTest::keyClick(window, Qt::Key_Right);
    QTRY_COMPARE(chips->property("currentIndex").toInt(), 1);
    QTest::keyClick(window, Qt::Key_Right);
    QTRY_COMPARE(chips->property("currentIndex").toInt(), 2);
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_COMPARE(apps->property("filter").toString(), QStringLiteral("Web"));

    // Down returns to the filtered grid rather than stranding focus.
    QTest::keyClick(window, Qt::Key_Down);
    QTRY_VERIFY2(grid->hasActiveFocus(), "Down did not return to the app grid");
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
    QCoreApplication::setApplicationName(QStringLiteral("HomeNavigationTest"));

    QGuiApplication app(argc, argv);
    HomeNavigationTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_home_navigation.moc"
