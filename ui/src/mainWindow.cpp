#include "mainWindow.h"
#include "settings.h"

#include <QFile>
#include <QFormLayout>
#include <QThread>
#include <QTimer>
#include <QVBoxLayout>

namespace {

QByteArray loadArt()
{
    return QFile(":/loading.aseprite").readAll();
}

}

MainWindow::MainWindow()
    : animation_(loadArt()), guest_(this)
{
    const Settings settings = readSettings();

    art_ = new QLabel;
    art_->setAlignment(Qt::AlignCenter);
    status_ = new QLabel("stopped");
    status_->setAlignment(Qt::AlignCenter);
    toggle_ = new QPushButton("Start");

    cores_ = new QSpinBox;
    cores_->setRange(1, QThread::idealThreadCount());
    cores_->setValue(settings.cores);
    mem_ = new QComboBox;
    mem_->setEditable(true);
    mem_->addItems(memoryOptions);
    mem_->setCurrentText(settings.mem);
    audio_ = new QCheckBox("audio");
    audio_->setChecked(settings.audio);

    auto *form = new QFormLayout;
    form->addRow("cores", cores_);
    form->addRow("mem", mem_);
    form->addRow("", audio_);

    auto *layout = new QVBoxLayout(this);
    layout->addWidget(art_);
    layout->addWidget(status_);
    layout->addWidget(toggle_);
    layout->addLayout(form);
    setWindowTitle("playground");

    clock_.start();
    auto *timer = new QTimer(this);
    connect(timer, &QTimer::timeout, this, [this] { art_->setPixmap(animation_.frameAt(clock_.elapsed())); });
    timer->start(16);

    connect(toggle_, &QPushButton::clicked, this, [this] {
        if (guest_.state() == GuestState::Running) {
            guest_.stop();
        } else {
            guest_.start();
        }
    });
    connect(&guest_, &GuestProcess::changed, this, &MainWindow::showGuest);
    connect(cores_, &QSpinBox::valueChanged, this, [this] { saveSettings(); });
    connect(mem_, &QComboBox::currentTextChanged, this, [this] { saveSettings(); });
    connect(audio_, &QCheckBox::toggled, this, [this] { saveSettings(); });
}

void MainWindow::saveSettings()
{
    if (!writeSettings({cores_->value(), mem_->currentText(), audio_->isChecked()})) {
        status_->setText("could not save settings");
    }
}

void MainWindow::showGuest(GuestState state, const QString &message)
{
    status_->setText(message);
    toggle_->setEnabled(state != GuestState::Preparing);
    toggle_->setText(state == GuestState::Running ? "Stop" : state == GuestState::Preparing ? "Starting" : "Start");
}
