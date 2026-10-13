#pragma once

#include <QString>
#include <QStringList>

struct Settings
{
    int cores;
    QString mem;
    bool audio;
};

inline const QStringList memoryOptions = {"2G", "4G", "6G", "8G", "12G", "16G", "24G"};

Settings readSettings();
bool writeSettings(const Settings &settings);
