// Regression test for first-boot input.
//
// The wizard is an overlay inside the launcher Window.  It is easy for a
// focus call in Main.qml to leave active focus on the overlay item instead of
// on the visible ActionList, in which case arrow keys and Enter silently do
// nothing on a real television.  This test loads the production QML and sends
// the same key events a USB keyboard or D-pad remote produces.

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
}

class WizardFocusTest : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void firstBootWizardAcceptsRemoteKeys();
    void finishingTheWizardActivatesHome();

private:
    // The engine must be destroyed before the context objects it points at.
    AppCatalog m_catalog;
    ControlClient m_control;
    HomeRelay m_homeRelay;
    QQmlApplicationEngine m_engine;
};

void WizardFocusTest::initTestCase()
{
    const QString qmlDir = qEnvironmentVariable("PIVISTA_QML_DIR",
                                                QString::fromUtf8(kQmlDir));
    m_engine.rootContext()->setContextProperty(QStringLiteral("catalog"), &m_catalog);
    m_engine.rootContext()->setContextProperty(QStringLiteral("control"), &m_control);
    m_engine.rootContext()->setContextProperty(QStringLiteral("homeRelay"), &m_homeRelay);
    m_engine.rootContext()->setContextProperty(QStringLiteral("windowedMode"), true);
    m_engine.rootContext()->setContextProperty(QStringLiteral("qmlDirectory"), qmlDir);
    m_engine.rootContext()->setContextProperty(QStringLiteral("uiDevMode"), false);
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

void WizardFocusTest::firstBootWizardAcceptsRemoteKeys()
{
    auto *window = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    QVERIFY(window);
    QTRY_VERIFY(window->isVisible());

    auto *wizard = window->findChild<QObject *>(QStringLiteral("wizard"));
    QVERIFY2(wizard, "wizard overlay was not found");
    auto *nav = wizard->findChild<QObject *>(QStringLiteral("wizardNav"));
    QVERIFY2(nav, "wizard navigation list was not found");

    // Let the two queued focus calls in Main.qml and WizardScreen.qml settle.
    QTest::qWait(300);
    QCOMPARE(wizard->property("step").toInt(), 0);
    QCOMPARE(nav->property("currentIndex").toInt(), 0);

    // Active focus must be on the navigation ListView, not on the plain
    // wizard Item.  The wizard-level fallback can keep keys working, but a
    // visible focus ring still belongs to the list the user is selecting.
    bool navFocused = false;
    for (auto *item : nav->findChildren<QQuickItem *>()) {
        if (item->hasActiveFocus()) {
            navFocused = true;
            break;
        }
    }
    QVERIFY2(navFocused, "wizard navigation list does not have active focus");

    // Down must move inside the wizard, not vanish into the overlay item.
    QTest::keyClick(window, Qt::Key_Down);
    QTRY_COMPARE(nav->property("currentIndex").toInt(), 1);

    QTest::keyClick(window, Qt::Key_Up);
    QTRY_COMPARE(nav->property("currentIndex").toInt(), 0);

    // Enter on Continue advances to the language step.
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_COMPARE(wizard->property("step").toInt(), 1);

    // Escape goes back rather than being swallowed.
    QTest::keyClick(window, Qt::Key_Escape);
    QTRY_COMPARE(wizard->property("step").toInt(), 0);

    // KEY_SELECT is what some TV remotes send for OK.
    QTest::keyClick(window, Qt::Key_Select);
    QTRY_COMPARE(wizard->property("step").toInt(), 1);

    // Backspace is documented as Back and must work as well.
    QTest::keyClick(window, Qt::Key_Backspace);
    QTRY_COMPARE(wizard->property("step").toInt(), 0);
}

void WizardFocusTest::finishingTheWizardActivatesHome()
{
    auto *window = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    QVERIFY(window);
    auto *wizard = window->findChild<QObject *>(QStringLiteral("wizard"));
    QVERIFY(wizard);

    // The launcher unloads the home screen while the wizard is visible so the
    // two cannot fight over active focus.  Finishing must load it again and
    // put focus on the featured banner without another key press.
    QVERIFY(QMetaObject::invokeMethod(wizard, "finish", Qt::DirectConnection));
    QTRY_VERIFY_WITH_TIMEOUT(!wizard->property("visible").toBool(), 5000);

    auto *banner = window->findChild<QQuickItem *>(QStringLiteral("featuredBanner"));
    QTRY_VERIFY_WITH_TIMEOUT(banner != nullptr, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(banner->hasActiveFocus(), 5000);
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
    QCoreApplication::setApplicationName(QStringLiteral("WizardFocusTest"));

    QGuiApplication app(argc, argv);
    WizardFocusTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_wizard_focus.moc"
