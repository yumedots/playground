local shared = shared

add_requires("qt6widgets", {system = true})

target("playground")
    set_kind("binary")
    set_default(true)
    set_languages("c++20")
    add_rules("qt.widgetapp")
    add_packages("qt6widgets")
    add_includedirs("vendor/cuteAseprite")
    add_files("src/*.cpp", "src/*.h", "resources.qrc")
    set_rundir(shared.projectdir)

target("checks")
    set_kind("binary")
    set_default(false)
    set_languages("c++20")
    add_rules("qt.widgetapp")
    add_packages("qt6widgets")
    add_includedirs("src", "vendor/cuteAseprite")
    add_files("src/*.cpp|main.cpp", "src/*.h", "tests/*.cpp")
    set_rundir(shared.projectdir)
