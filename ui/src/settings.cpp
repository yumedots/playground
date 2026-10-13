#include "settings.h"
#include "paths.h"

#include <QDir>
#include <QFile>
#include <QSysInfo>
#include <QTextStream>
#include <QThread>

#include <algorithm>
#include <unistd.h>

namespace {

Settings defaults()
{
    const qint64 gigabytes = sysconf(_SC_PHYS_PAGES) * sysconf(_SC_PAGESIZE) / (1LL << 30);

    return {
        std::min(8, QThread::idealThreadCount()),
        gigabytes >= 16 ? QString("8G") : QString("4G"),
        QSysInfo::productType() == "macos",
    };
}

}

Settings readSettings()
{
    Settings settings = defaults();
    QFile file(stateDir() + "/settings");
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return settings;
    }
    for (const QString &line : QString::fromUtf8(file.readAll()).split('\n')) {
        const int split = line.indexOf('=');
        if (split < 0) {
            continue;
        }
        const QString key = line.left(split).trimmed();
        const QString value = line.mid(split + 1).trimmed();
        bool ok = false;
        if (key == "cores") {
            const int cores = value.toInt(&ok);
            if (ok) {
                settings.cores = cores;
            }
        } else if (key == "mem") {
            settings.mem = value;
        } else if (key == "audio") {
            settings.audio = value == "on";
        }
    }
    return settings;
}

bool writeSettings(const Settings &settings)
{
    QDir().mkpath(stateDir());
    QFile file(stateDir() + "/settings");
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }
    QTextStream(&file) << "cores=" << settings.cores << "\nmem=" << settings.mem
                       << "\naudio=" << (settings.audio ? "on" : "off") << "\n";
    return true;
}
