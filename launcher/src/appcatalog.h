#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>

class AppCatalog : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY changed)
    Q_PROPERTY(QVariantList recent READ recent NOTIFY changed)
    Q_PROPERTY(QVariantList streaming READ streaming NOTIFY changed)
    Q_PROPERTY(QVariantList nativeApps READ nativeApps NOTIFY changed)
    Q_PROPERTY(QVariantList allApps READ allApps NOTIFY changed)
    Q_PROPERTY(bool externalAppActive READ externalAppActive NOTIFY externalAppChanged)
    Q_PROPERTY(QString externalAppName READ externalAppName NOTIFY externalAppChanged)

public:
    explicit AppCatalog(QObject *parent = nullptr);

    QVariantList apps() const;
    QVariantList favorites() const;
    QVariantList recent() const;
    QVariantList streaming() const;
    QVariantList nativeApps() const;
    QVariantList allApps() const;
    bool externalAppActive() const { return m_externalActive; }
    QString externalAppName() const { return m_externalName; }

    Q_INVOKABLE void reload();
    Q_INVOKABLE void launch(const QString &id);
    Q_INVOKABLE void toggleFavorite(const QString &id);
    Q_INVOKABLE void setHidden(const QString &id, bool hidden);
    Q_INVOKABLE void closeExternalApp();
    Q_INVOKABLE QVariantMap application(const QString &id) const;
    Q_INVOKABLE void clearBrowserData();
    Q_INVOKABLE QStringList availableCategories() const;
    Q_INVOKABLE QString addWebApp(const QString &name, const QString &url);
    Q_INVOKABLE QString removeWebApp(const QString &id);

    static bool validWebUrl(const QString &text, QString *error = nullptr);

signals:
    void changed();
    void externalAppChanged();
    void launchFailed(const QString &message);
    void launched(const QString &id);
    void launchFinished(const QString &id);

private:
    struct Entry {
        QString id;
        QString name;
        QString shortName;
        QString color;
        QString kind;        // native | web | android
        QString icon;        // theme name or file path
        QString category;
        QString comment;
        QString compatibility;
        QString notes;
        QString exec;
        QString program;
        QStringList arguments;
        QString url;
        QString profile;
        bool kiosk = false;
        bool valid = true;
        QString problem;
    };

    void scanDesktopEntries();
    void scanWebApps();
    void loadPreferences();
    void savePreferences() const;
    QStringList preferenceList(const QString &key) const;
    void setPreferenceList(const QString &key, const QStringList &values);
    QVariantMap toMap(const Entry &entry) const;
    QVariantList listFor(const QStringList &ids) const;
    const Entry *find(const QString &id) const;
    QString resolvedIcon(const Entry &entry) const;
    bool startProcess(const QString &program, const QStringList &arguments,
                      const QString &id, const QString &name, const QString &workingDir = {});

    QList<Entry> m_entries;
    QStringList m_favoriteIds;
    QStringList m_recentIds;
    QStringList m_hiddenIds;
    QProcess *m_process = nullptr;
    bool m_externalActive = false;
    QString m_externalName;
    QString m_activeId;
};
