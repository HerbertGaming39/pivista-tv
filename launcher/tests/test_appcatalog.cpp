#include "appcatalog.h"

#include <QDir>
#include <QFile>
#include <QSettings>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantList>
#include <QVariantMap>

class AppCatalogTest : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void init();
    void validHttpsUrls();
    void rejectsUnsafeUrls();
    void discoversDesktopEntries();
    void rejectsTerminalAndMissingPrograms();
    void favouritesAndHiddenPersist();
    void launchesNativeAppAndRecordsRecent();

private:
    QTemporaryDir m_dir;
    QString m_appsDir;
};

void AppCatalogTest::initTestCase()
{
    QVERIFY(m_dir.isValid());
    QStandardPaths::setTestModeEnabled(true);
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_dir.path() + "/config");
    m_appsDir = m_dir.path() + "/applications";
    QDir().mkpath(m_appsDir);
    qputenv("PIVISTA_APPLICATION_DIRS", m_appsDir.toUtf8());
    qputenv("PIVISTA_WEBAPP_CATALOG", (m_dir.path() + "/missing.json").toUtf8());

    auto write = [this](const QString &name, const QString &body) {
        QFile file(m_appsDir + "/" + name);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(body.toUtf8());
    };
    write("player.desktop",
          "[Desktop Entry]\nType=Application\nName=Test Player\n"
          "Comment=Plays local media\nExec=/bin/true --flag %U\nIcon=media-playback-start\n"
          "Categories=AudioVideo;\n");
    write("terminal.desktop",
          "[Desktop Entry]\nType=Application\nName=Terminal Tool\nExec=/bin/true\nTerminal=true\n");
    write("missing.desktop",
          "[Desktop Entry]\nType=Application\nName=Missing Tool\nExec=/definitely/not/installed\n");
    write("game.desktop",
          "[Desktop Entry]\nType=Application\nName=Test Game\nExec=/bin/true\n"
          "Categories=Game;\n");
    write("hidden.desktop",
          "[Desktop Entry]\nType=Application\nName=Hidden Tool\nExec=/bin/true\nNoDisplay=true\n");
}

void AppCatalogTest::init()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

void AppCatalogTest::validHttpsUrls()
{
    QString error;
    QVERIFY(AppCatalog::validWebUrl(QStringLiteral("https://www.netflix.com/browse"), &error));
    QVERIFY(error.isEmpty());
    QVERIFY(AppCatalog::validWebUrl(QStringLiteral("https://vod.tvp.pl/"), nullptr));
}

void AppCatalogTest::rejectsUnsafeUrls()
{
    const QStringList bad = {
        QStringLiteral("http://www.netflix.com"),
        QStringLiteral("javascript:alert(1)"),
        QStringLiteral("file:///etc/passwd"),
        QStringLiteral("https://user:pass@example.com/"),
        QStringLiteral("https://"),
        QString(),
    };
    for (const QString &url : bad) {
        QString error;
        QVERIFY2(!AppCatalog::validWebUrl(url, &error), qPrintable("accepted: " + url));
        QVERIFY2(!error.isEmpty(), qPrintable("no error for: " + url));
    }
}

void AppCatalogTest::discoversDesktopEntries()
{
    AppCatalog catalog;
    const QVariantList apps = catalog.apps();
    QStringList names;
    for (const QVariant &value : apps)
        names << value.toMap().value("name").toString();
    QVERIFY(names.contains("Test Player"));
    QVERIFY(!names.contains("Hidden Tool"));
    QVERIFY(!names.contains("Terminal Tool"));
    QVERIFY(!names.contains("Missing Tool"));

    const QVariantMap player = catalog.application("native:player");
    QCOMPARE(player.value("kind").toString(), QStringLiteral("native"));
    QCOMPARE(player.value("category").toString(), QStringLiteral("Media"));
    QVERIFY(player.value("installed").toBool());
    QVERIFY(!player.value("web").toBool());
    QVERIFY(player.value("valid").toBool());
    QCOMPARE(player.value("icon").toString(), QStringLiteral("image://pivistaicon/media-playback-start"));

    const QVariantList games = catalog.games();
    QCOMPARE(games.size(), 1);
    QCOMPARE(games.first().toMap().value("name").toString(), QStringLiteral("Test Game"));

    const QVariantList media = catalog.mediaApps();
    QCOMPARE(media.size(), 1);
    QCOMPARE(media.first().toMap().value("name").toString(), QStringLiteral("Test Player"));
}

void AppCatalogTest::rejectsTerminalAndMissingPrograms()
{
    AppCatalog catalog;
    const QVariantMap terminal = catalog.application("native:terminal");
    QVERIFY(!terminal.value("valid").toBool());
    QVERIFY(terminal.value("problem").toString().contains("terminal", Qt::CaseInsensitive));

    const QVariantMap missing = catalog.application("native:missing");
    QVERIFY(!missing.value("valid").toBool());
    QVERIFY(!missing.value("problem").toString().isEmpty());

    // A television must not render dead tiles for entries it cannot launch.
    const QVariantList listed = catalog.apps();
    QStringList listedIds;
    for (const QVariant &value : listed)
        listedIds << value.toMap().value("id").toString();
    QVERIFY(!listedIds.contains("native:terminal"));
    QVERIFY(!listedIds.contains("native:missing"));

    const QVariantList managed = catalog.allApps();
    QStringList managedIds;
    for (const QVariant &value : managed)
        managedIds << value.toMap().value("id").toString();
    QVERIFY(!managedIds.contains("native:terminal"));
    QVERIFY(!managedIds.contains("native:missing"));
}

void AppCatalogTest::favouritesAndHiddenPersist()
{
    {
        AppCatalog catalog;
        catalog.toggleFavorite("native:player");
        QCOMPARE(catalog.favorites().size(), 1);
        QCOMPARE(catalog.featured().value("id").toString(), QStringLiteral("native:player"));
        catalog.setHidden("native:player", true);
        QCOMPARE(catalog.favorites().size(), 0);
        QVERIFY(!catalog.application("native:player").isEmpty());
        QVERIFY(catalog.application("native:player").value("hidden").toBool());
    }
    {
        AppCatalog reloaded;
        reloaded.reload();
        QVERIFY(reloaded.application("native:player").value("hidden").toBool());
        reloaded.setHidden("native:player", false);
        QVERIFY(!reloaded.application("native:player").value("hidden").toBool());
    }
}

void AppCatalogTest::launchesNativeAppAndRecordsRecent()
{
    AppCatalog catalog;
    QSignalSpy finished(&catalog, &AppCatalog::launchFinished);
    catalog.launch(QStringLiteral("native:player"));
    QTRY_COMPARE_WITH_TIMEOUT(finished.count(), 1, 4000);
    QVERIFY(!catalog.externalAppActive());
    QCOMPARE(catalog.recent().size(), 1);
    QCOMPARE(catalog.recent().first().toMap().value("id").toString(),
             QStringLiteral("native:player"));
}

QTEST_GUILESS_MAIN(AppCatalogTest)
#include "test_appcatalog.moc"
