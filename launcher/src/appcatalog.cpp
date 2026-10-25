#include "appcatalog.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <algorithm>

namespace {
constexpr int kRecentLimit = 10;
const QStringList kDefaultFavorites = {
    QStringLiteral("web.netflix"), QStringLiteral("web.youtube"),
    QStringLiteral("web.disneyplus"), QStringLiteral("web.primevideo"),
    QStringLiteral("web.tvpvod"),
};

QString slugify(const QString &text)
{
    QString slug = text.toLower();
    slug.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    return slug.trimmed().replace(QRegularExpression(QStringLiteral("^-+|-+$")), QString());
}
} // namespace

AppCatalog::AppCatalog(QObject *parent)
    : QObject(parent)
{
    loadPreferences();
    reload();
}

void AppCatalog::reload()
{
    m_entries.clear();
    scanDesktopEntries();
    scanWebApps();

    std::stable_sort(m_entries.begin(), m_entries.end(), [](const Entry &a, const Entry &b) {
        if (a.kind != b.kind)
            return a.kind == QLatin1String("web"); // keep curated streaming order on top
        if (a.kind == QLatin1String("web"))
            return false;
        return a.name.localeAwareCompare(b.name) < 0;
    });

    if (m_favoriteIds.isEmpty() && !preferenceList(QStringLiteral("favorites_seeded")).size()) {
        QStringList seed;
        for (const QString &id : kDefaultFavorites) {
            if (find(id))
                seed << id;
        }
        if (!seed.isEmpty()) {
            m_favoriteIds = seed;
            setPreferenceList(QStringLiteral("favorites"), m_favoriteIds);
            setPreferenceList(QStringLiteral("favorites_seeded"), {QStringLiteral("1")});
        }
    }
    emit changed();
}

void AppCatalog::scanDesktopEntries()
{
    QStringList directories = {
        QStringLiteral("/usr/share/applications"),
        QStringLiteral("/usr/local/share/applications"),
        QDir::homePath() + QStringLiteral("/.local/share/applications"),
    };
    const QString extra = qEnvironmentVariable("PIVISTA_APPLICATION_DIRS");
    if (!extra.isEmpty())
        directories = extra.split(QLatin1Char(':'), Qt::SkipEmptyParts);

    QSet<QString> seen;
    for (const QString &directory : directories) {
        QDir dir(directory);
        if (!dir.exists())
            continue;
        const QFileInfoList files = dir.entryInfoList({QStringLiteral("*.desktop")}, QDir::Files, QDir::Name);
        for (const QFileInfo &file : files) {
            QSettings desktop(file.absoluteFilePath(), QSettings::IniFormat);
            if (!desktop.childGroups().contains(QStringLiteral("Desktop Entry")))
                continue;
            desktop.beginGroup(QStringLiteral("Desktop Entry"));
            if (desktop.value(QStringLiteral("Type")).toString() != QLatin1String("Application"))
                continue;
            if (desktop.value(QStringLiteral("NoDisplay"), false).toBool()
                || desktop.value(QStringLiteral("Hidden"), false).toBool())
                continue;

            const QString name = desktop.value(QStringLiteral("Name")).toString().trimmed();
            const QString rawExec = desktop.value(QStringLiteral("Exec")).toString().trimmed();
            if (name.isEmpty() || rawExec.isEmpty())
                continue;

            const QString id = QStringLiteral("native:") + file.completeBaseName();
            if (seen.contains(id))
                continue;
            seen.insert(id);

            Entry entry;
            entry.id = id;
            entry.name = name;
            entry.kind = QStringLiteral("native");
            entry.icon = desktop.value(QStringLiteral("Icon")).toString();
            entry.comment = desktop.value(QStringLiteral("Comment")).toString();
            entry.category = QStringLiteral("Applications");
            entry.compatibility = QStringLiteral("native");
            entry.exec = rawExec;
            entry.shortName = name.left(1).toUpper();

            QString exec = rawExec;
            exec.remove(QRegularExpression(QStringLiteral("%[fFuUdDnNickvm]")));
            const QStringList parts = QProcess::splitCommand(exec);
            if (parts.isEmpty()) {
                entry.valid = false;
                entry.problem = QStringLiteral("The application entry has no launch command.");
            } else if (desktop.value(QStringLiteral("Terminal"), false).toBool()) {
                entry.valid = false;
                entry.problem = QStringLiteral("This application requires a terminal window.");
            } else {
                const QString program = parts.first();
                QString resolved;
                if (program.startsWith(QLatin1Char('/'))) {
                    const QFileInfo info(program);
                    if (info.isExecutable())
                        resolved = info.absoluteFilePath();
                } else {
                    resolved = QStandardPaths::findExecutable(program);
                }
                if (resolved.isEmpty()) {
                    entry.valid = false;
                    entry.problem = QStringLiteral("The launch command is not installed.");
                } else {
                    entry.program = resolved;
                    entry.arguments = parts.mid(1);
                }
            }
            m_entries.append(entry);
        }
    }
}

void AppCatalog::scanWebApps()
{
    QString catalogPath = qEnvironmentVariable("PIVISTA_WEBAPP_CATALOG");
    if (catalogPath.isEmpty())
        catalogPath = QStringLiteral("/usr/share/pivista/webapps/catalog.json");

    auto addFromArray = [this](const QJsonArray &array, bool userProvided) {
        for (const QJsonValue &value : array) {
            const QJsonObject object = value.toObject();
            Entry entry;
            entry.name = object.value(QStringLiteral("name")).toString().trimmed();
            entry.url = object.value(QStringLiteral("url")).toString().trimmed();
            entry.shortName = object.value(QStringLiteral("short")).toString().trimmed();
            entry.color = object.value(QStringLiteral("color")).toString().trimmed();
            entry.category = object.value(QStringLiteral("category")).toString().trimmed();
            entry.notes = object.value(QStringLiteral("notes")).toString().trimmed();
            entry.compatibility = object.value(QStringLiteral("compatibility")).toString().trimmed();
            entry.profile = object.value(QStringLiteral("profile")).toString().trimmed();
            entry.kiosk = object.value(QStringLiteral("kiosk")).toBool(true);
            entry.kind = QStringLiteral("web");
            entry.id = object.value(QStringLiteral("id")).toString().trimmed();
            if (entry.name.isEmpty() || entry.url.isEmpty())
                continue;
            if (entry.id.isEmpty())
                entry.id = QStringLiteral("web.user.") + slugify(entry.name);
            if (entry.shortName.isEmpty())
                entry.shortName = entry.name.left(2).toUpper();
            if (entry.color.isEmpty())
                entry.color = QStringLiteral("#2563eb");
            if (entry.compatibility.isEmpty())
                entry.compatibility = QStringLiteral("web");
            if (entry.profile.isEmpty())
                entry.profile = slugify(entry.name);
            QString error;
            if (!validWebUrl(entry.url, &error)) {
                entry.valid = false;
                entry.problem = error;
            }
            entry.comment = userProvided ? QStringLiteral("User web shortcut") : QStringLiteral("Web application");
            if (find(entry.id) == nullptr)
                m_entries.append(entry);
        }
    };

    QFile systemFile(catalogPath);
    if (systemFile.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(systemFile.readAll());
        addFromArray(doc.object().value(QStringLiteral("apps")).toArray(), false);
    }

    const QString userPath = QDir::homePath() + QStringLiteral("/.config/pivista/webapps.json");
    QFile userFile(userPath);
    if (userFile.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(userFile.readAll());
        const QJsonArray array = doc.isArray() ? doc.array() : doc.object().value(QStringLiteral("apps")).toArray();
        addFromArray(array, true);
    }
}

bool AppCatalog::validWebUrl(const QString &text, QString *error)
{
    if (text.isEmpty() || text.size() > 2048) {
        if (error) *error = QStringLiteral("The address is empty or too long.");
        return false;
    }
    const QUrl url(text, QUrl::StrictMode);
    if (!url.isValid()) {
        if (error) *error = QStringLiteral("That is not a valid address.");
        return false;
    }
    if (url.scheme() != QLatin1String("https")) {
        if (error) *error = QStringLiteral("Only https:// addresses are allowed.");
        return false;
    }
    if (url.host().isEmpty() || !url.userInfo().isEmpty()) {
        if (error) *error = QStringLiteral("The address must have a host and no credentials.");
        return false;
    }
    return true;
}

QVariantMap AppCatalog::toMap(const Entry &entry) const
{
    QVariantMap map;
    map.insert(QStringLiteral("id"), entry.id);
    map.insert(QStringLiteral("name"), entry.name);
    map.insert(QStringLiteral("short"), entry.shortName);
    map.insert(QStringLiteral("color"), entry.color);
    map.insert(QStringLiteral("kind"), entry.kind);
    map.insert(QStringLiteral("icon"), resolvedIcon(entry));
    map.insert(QStringLiteral("category"), entry.category.isEmpty() ? QStringLiteral("Applications") : entry.category);
    map.insert(QStringLiteral("comment"), entry.comment);
    map.insert(QStringLiteral("compatibility"), entry.compatibility);
    map.insert(QStringLiteral("notes"), entry.notes);
    map.insert(QStringLiteral("valid"), entry.valid);
    map.insert(QStringLiteral("problem"), entry.problem);
    map.insert(QStringLiteral("favorite"), m_favoriteIds.contains(entry.id));
    map.insert(QStringLiteral("hidden"), m_hiddenIds.contains(entry.id));
    map.insert(QStringLiteral("url"), entry.url);
    return map;
}

QString AppCatalog::resolvedIcon(const Entry &entry) const
{
    if (entry.icon.isEmpty())
        return {};
    if (entry.icon.startsWith(QLatin1Char('/'))) {
        if (QFileInfo::exists(entry.icon))
            return QStringLiteral("file://") + entry.icon;
        return {};
    }
    return QStringLiteral("image://pivistaicon/") + entry.icon;
}

const AppCatalog::Entry *AppCatalog::find(const QString &id) const
{
    for (const Entry &entry : m_entries) {
        if (entry.id == id)
            return &entry;
    }
    return nullptr;
}

QVariantList AppCatalog::listFor(const QStringList &ids) const
{
    QVariantList result;
    for (const QString &id : ids) {
        const Entry *entry = find(id);
        if (!entry || m_hiddenIds.contains(id))
            continue;
        result.append(toMap(*entry));
    }
    return result;
}

QVariantList AppCatalog::apps() const
{
    QVariantList result;
    for (const Entry &entry : m_entries) {
        if (m_hiddenIds.contains(entry.id))
            continue;
        result.append(toMap(entry));
    }
    return result;
}

QVariantList AppCatalog::allApps() const
{
    QVariantList result;
    for (const Entry &entry : m_entries)
        result.append(toMap(entry));
    return result;
}

void AppCatalog::clearBrowserData()
{
    const QString path = QDir::homePath() + QStringLiteral("/.config/pivista/browser");
    QDir directory(path);
    if (directory.exists())
        directory.removeRecursively();
    QDir().mkpath(path);
}

QVariantList AppCatalog::favorites() const { return listFor(m_favoriteIds); }
QVariantList AppCatalog::recent() const { return listFor(m_recentIds); }

QVariantList AppCatalog::streaming() const
{
    QVariantList result;
    for (const Entry &entry : m_entries) {
        if (entry.kind != QLatin1String("web") || m_hiddenIds.contains(entry.id))
            continue;
        result.append(toMap(entry));
    }
    return result;
}

QVariantList AppCatalog::nativeApps() const
{
    QVariantList result;
    for (const Entry &entry : m_entries) {
        if (entry.kind != QLatin1String("native") || m_hiddenIds.contains(entry.id))
            continue;
        result.append(toMap(entry));
    }
    return result;
}

QVariantMap AppCatalog::application(const QString &id) const
{
    const Entry *entry = find(id);
    return entry ? toMap(*entry) : QVariantMap{};
}

QStringList AppCatalog::availableCategories() const
{
    QStringList categories;
    for (const Entry &entry : m_entries) {
        if (!entry.category.isEmpty() && !categories.contains(entry.category))
            categories << entry.category;
    }
    categories.sort();
    return categories;
}

void AppCatalog::launch(const QString &id)
{
    const Entry *entry = find(id);
    if (!entry) {
        emit launchFailed(tr("That application is no longer installed."));
        return;
    }
    if (!entry->valid) {
        emit launchFailed(entry->problem.isEmpty() ? tr("This application cannot be started.") : entry->problem);
        return;
    }

    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->terminate();
        if (!m_process->waitForFinished(1200))
            m_process->kill();
    }

    if (entry->kind == QLatin1String("web")) {
        const QString chromium = QStandardPaths::findExecutable(QStringLiteral("chromium"));
        if (chromium.isEmpty()) {
            emit launchFailed(tr("Chromium is not installed on this system."));
            return;
        }
        const QString profile = entry->profile.isEmpty() ? slugify(entry->name) : entry->profile;
        const QString profileDir = QDir::homePath() + QStringLiteral("/.config/pivista/browser/") + profile;
        QDir().mkpath(profileDir);
        QFile::setPermissions(profileDir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

        QStringList args = {
            QStringLiteral("--ozone-platform=wayland"),
            QStringLiteral("--kiosk"),
            QStringLiteral("--start-fullscreen"),
            QStringLiteral("--app=") + entry->url,
            QStringLiteral("--class=pivista-webapp"),
            QStringLiteral("--user-data-dir=") + profileDir,
            QStringLiteral("--no-first-run"),
            QStringLiteral("--no-default-browser-check"),
            QStringLiteral("--noerrdialogs"),
            QStringLiteral("--disable-session-crashed-bubble"),
            QStringLiteral("--password-store=basic"),
        };
        if (!startProcess(chromium, args, id, entry->name))
            return;
    } else {
        if (entry->program.isEmpty()) {
            emit launchFailed(tr("This application has no launch command."));
            return;
        }
        if (!startProcess(entry->program, entry->arguments, id, entry->name, QDir::homePath()))
            return;
    }

    m_recentIds.removeAll(id);
    m_recentIds.prepend(id);
    while (m_recentIds.size() > kRecentLimit)
        m_recentIds.removeLast();
    setPreferenceList(QStringLiteral("recent"), m_recentIds);
    emit launched(id);
    emit changed();
}

bool AppCatalog::startProcess(const QString &program, const QStringList &arguments,
                              const QString &id, const QString &name, const QString &workingDir)
{
    if (m_process) {
        m_process->deleteLater();
        m_process = nullptr;
    }
    m_process = new QProcess(this);
    m_process->setProgram(program);
    m_process->setArguments(arguments);
    m_process->setProcessChannelMode(QProcess::ForwardedChannels);
    if (!workingDir.isEmpty())
        m_process->setWorkingDirectory(workingDir);

    m_activeId = id;
    m_externalName = name;
    connect(m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        Q_UNUSED(code)
        Q_UNUSED(status)
        m_externalActive = false;
        const QString finishedId = m_activeId;
        m_activeId.clear();
        emit externalAppChanged();
        emit launchFinished(finishedId);
    });
    connect(m_process, &QProcess::errorOccurred, this, [this, name](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_externalActive = false;
            emit externalAppChanged();
            emit launchFailed(tr("%1 could not be started.").arg(name));
        }
    });

    m_externalActive = true;
    emit externalAppChanged();
    m_process->start();
    if (!m_process->waitForStarted(4000)) {
        m_externalActive = false;
        emit externalAppChanged();
        emit launchFailed(tr("%1 could not be started.").arg(name));
        return false;
    }
    return true;
}

void AppCatalog::closeExternalApp()
{
    if (!m_process || m_process->state() == QProcess::NotRunning)
        return;
    m_process->terminate();
    QTimer::singleShot(1500, m_process, [process = m_process]() {
        if (process->state() != QProcess::NotRunning)
            process->kill();
    });
}

void AppCatalog::toggleFavorite(const QString &id)
{
    if (!find(id))
        return;
    if (m_favoriteIds.contains(id))
        m_favoriteIds.removeAll(id);
    else
        m_favoriteIds.append(id);
    setPreferenceList(QStringLiteral("favorites"), m_favoriteIds);
    emit changed();
}

void AppCatalog::setHidden(const QString &id, bool hidden)
{
    if (!find(id))
        return;
    if (hidden) {
        if (!m_hiddenIds.contains(id))
            m_hiddenIds.append(id);
        m_favoriteIds.removeAll(id);
        setPreferenceList(QStringLiteral("favorites"), m_favoriteIds);
    } else {
        m_hiddenIds.removeAll(id);
    }
    setPreferenceList(QStringLiteral("hidden"), m_hiddenIds);
    emit changed();
}

QString AppCatalog::addWebApp(const QString &name, const QString &url)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty() || trimmed.size() > 60)
        return tr("The name must be between 1 and 60 characters.");
    QString error;
    if (!validWebUrl(url.trimmed(), &error))
        return error;

    QString id = QStringLiteral("web.user.") + slugify(trimmed);
    if (find(id))
        id += QStringLiteral("-") + QString::number(QDateTime::currentMSecsSinceEpoch() % 100000);

    const QString path = QDir::homePath() + QStringLiteral("/.config/pivista/webapps.json");
    QDir().mkpath(QFileInfo(path).absolutePath());
    QJsonArray array;
    QFile existing(path);
    if (existing.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(existing.readAll());
        array = doc.isArray() ? doc.array() : doc.object().value(QStringLiteral("apps")).toArray();
        existing.close();
    }
    QJsonObject object;
    object.insert(QStringLiteral("id"), id);
    object.insert(QStringLiteral("name"), trimmed);
    object.insert(QStringLiteral("url"), url.trimmed());
    object.insert(QStringLiteral("category"), QStringLiteral("Web"));
    object.insert(QStringLiteral("compatibility"), QStringLiteral("web"));
    object.insert(QStringLiteral("notes"), tr("User-added web shortcut. Playback depends on the site and DRM support."));
    object.insert(QStringLiteral("kiosk"), true);
    array.append(object);
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return tr("The shortcut could not be saved.");
    output.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    output.close();
    reload();
    return {};
}

QString AppCatalog::removeWebApp(const QString &id)
{
    if (!id.startsWith(QLatin1String("web.user.")))
        return tr("Only user-added shortcuts can be removed here.");
    const QString path = QDir::homePath() + QStringLiteral("/.config/pivista/webapps.json");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return tr("There is no user shortcut file to edit.");
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    QJsonArray array = doc.isArray() ? doc.array() : doc.object().value(QStringLiteral("apps")).toArray();
    file.close();
    bool removed = false;
    for (int i = array.size() - 1; i >= 0; --i) {
        if (array.at(i).toObject().value(QStringLiteral("id")).toString() == id) {
            array.removeAt(i);
            removed = true;
        }
    }
    if (!removed)
        return tr("That shortcut was not found.");
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return tr("The shortcut file could not be updated.");
    output.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    output.close();
    m_favoriteIds.removeAll(id);
    m_recentIds.removeAll(id);
    setPreferenceList(QStringLiteral("favorites"), m_favoriteIds);
    setPreferenceList(QStringLiteral("recent"), m_recentIds);
    reload();
    return {};
}

void AppCatalog::loadPreferences()
{
    m_favoriteIds = preferenceList(QStringLiteral("favorites"));
    m_recentIds = preferenceList(QStringLiteral("recent"));
    m_hiddenIds = preferenceList(QStringLiteral("hidden"));
}

QStringList AppCatalog::preferenceList(const QString &key) const
{
    QSettings settings;
    return settings.value(QStringLiteral("catalog/") + key).toStringList();
}

void AppCatalog::setPreferenceList(const QString &key, const QStringList &values)
{
    QSettings settings;
    settings.setValue(QStringLiteral("catalog/") + key, values);
    settings.sync();
}

void AppCatalog::savePreferences() const
{
    QSettings settings;
    settings.setValue(QStringLiteral("catalog/favorites"), m_favoriteIds);
    settings.setValue(QStringLiteral("catalog/recent"), m_recentIds);
    settings.setValue(QStringLiteral("catalog/hidden"), m_hiddenIds);
    settings.sync();
}
