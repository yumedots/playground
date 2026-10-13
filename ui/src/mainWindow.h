#pragma once

#include "guestProcess.h"
#include "loadingAnimation.h"

#include <QCheckBox>
#include <QComboBox>
#include <QElapsedTimer>
#include <QLabel>
#include <QPushButton>
#include <QSpinBox>
#include <QWidget>

class MainWindow : public QWidget
{
public:
    MainWindow();

private:
    void saveSettings();
    void showGuest(GuestState state, const QString &message);

    LoadingAnimation animation_;
    QElapsedTimer clock_;
    GuestProcess guest_;
    QLabel *art_;
    QLabel *status_;
    QPushButton *toggle_;
    QSpinBox *cores_;
    QComboBox *mem_;
    QCheckBox *audio_;
};
