#include "appcatalog.h"
#include "controlclient.h"
#include "iconprovider.h"

#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

namespace {
QString findQmlDirectory()
{
    const QString override = qEnvironmentVariable("PIVISTA_QML_DIR");
    if (!override.isEmpty() && QFileInfo::exists(override + QStringLiteral("/Main.qml")))
        return override;

    const QStringList candidates = {
        QStringLiteral("/usr/share/pivista/qml"),
        QCoreApplication::applicationDirPath() + QStringLiteral("/../qml"),
        QCoreApplication::applicationDirPath() + QStringLiteral("/qml"),
    };
    for (const QString &candidate : candidates) {
        if (QFileInfo::exists(candidate + QStringLiteral("/Main.qml")))
            return QDir(candidate).absolutePath();
    }
    return {};
}
} // namespace

int main(int argc, char *argv[])
{
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QLatin1String("--version")) {
            printf("PiVista TV launcher 0.1.0\n");
            return 0;
        }
    }

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("PiVista Launcher"));
    QGuiApplication::setOrganizationName(QStringLiteral("PiVista"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.0"));
    QGuiApplication::setDesktopFileName(QStringLiteral("pivista-launcher"));

    bool windowed = false;
    const QStringList arguments = QCoreApplication::arguments();
    for (const QString &argument : arguments) {
        if (argument == QLatin1String("--windowed"))
            windowed = true;
    }

    const QString qmlDirectory = findQmlDirectory();
    if (qmlDirectory.isEmpty()) {
        qCritical() << "pivista-launcher: no QML directory found (set PIVISTA_QML_DIR)";
        return 3;
    }

    AppCatalog catalog;
    ControlClient control;

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("pivistaicon"), new IconProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("catalog"), &catalog);
    engine.rootContext()->setContextProperty(QStringLiteral("control"), &control);
    engine.rootContext()->setContextProperty(QStringLiteral("windowedMode"), windowed);
    engine.rootContext()->setContextProperty(QStringLiteral("qmlDirectory"), qmlDirectory);
    engine.rootContext()->setContextProperty(QStringLiteral("uiDevMode"),
                                             qEnvironmentVariableIsSet("PIVISTA_UI_DEV"));
    engine.rootContext()->setContextProperty(QStringLiteral("screenshotPath"),
                                             qEnvironmentVariable("PIVISTA_SCREENSHOT"));
    engine.rootContext()->setContextProperty(QStringLiteral("initialScreen"),
                                             qEnvironmentVariable("PIVISTA_UI_SCREEN"));

    const QString screenshot = qEnvironmentVariable("PIVISTA_SCREENSHOT");
    if (!screenshot.isEmpty()) {
        QTimer::singleShot(1800, &app, [&engine, screenshot] {
            QImage image;
            if (!engine.rootObjects().isEmpty()) {
                if (auto *quickWindow = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
                    image = quickWindow->grabWindow();
            }
            if (!image.isNull() && image.save(screenshot))
                qInfo() << "screenshot written:" << screenshot;
            else
                qWarning() << "screenshot failed:" << screenshot;
            QCoreApplication::quit();
        });
    }

    engine.load(QUrl::fromLocalFile(qmlDirectory + QStringLiteral("/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "pivista-launcher: failed to load" << qmlDirectory + "/Main.qml";
        return 4;
    }
    return app.exec();
}
