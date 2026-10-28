#pragma once

#include <QDir>
#include <QString>

inline QString stateDir()
{
    return qEnvironmentVariable("PLAYGROUND_STATE_DIR", QDir::currentPath() + "/state");
}
