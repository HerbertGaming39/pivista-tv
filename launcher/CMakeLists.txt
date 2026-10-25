cmake_minimum_required(VERSION 3.16)
project(pivista-launcher VERSION 0.3.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick Network)

option(PIVISTA_BUILD_TESTS "Build launcher unit tests" OFF)

add_executable(pivista-launcher
    src/main.cpp
    src/appcatalog.cpp
    src/appcatalog.h
    src/controlclient.cpp
    src/controlclient.h
    src/iconprovider.cpp
    src/iconprovider.h
    src/homecontrol.cpp
    src/homecontrol.h
)

target_link_libraries(pivista-launcher PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network
)

target_compile_options(pivista-launcher PRIVATE -Wall -Wextra)

install(TARGETS pivista-launcher RUNTIME DESTINATION bin)

if(PIVISTA_BUILD_TESTS)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Test)
    enable_testing()
    add_executable(pivista-launcher-tests
        tests/test_appcatalog.cpp
        src/appcatalog.cpp
        src/appcatalog.h
    )
    target_include_directories(pivista-launcher-tests PRIVATE src)
    target_link_libraries(pivista-launcher-tests PRIVATE Qt6::Core Qt6::Test)
    add_test(NAME launcher-unit COMMAND pivista-launcher-tests)

    add_executable(pivista-home-tests
        tests/test_homecontrol.cpp
        src/homecontrol.cpp
        src/homecontrol.h
    )
    target_include_directories(pivista-home-tests PRIVATE src)
    target_link_libraries(pivista-home-tests PRIVATE Qt6::Core Qt6::Network Qt6::Test)
    add_test(NAME launcher-home COMMAND pivista-home-tests)

    add_executable(pivista-wizard-tests
        tests/test_wizard_focus.cpp
        src/appcatalog.cpp
        src/appcatalog.h
        src/controlclient.cpp
        src/controlclient.h
        src/homecontrol.cpp
        src/homecontrol.h
    )
    target_include_directories(pivista-wizard-tests PRIVATE src)
    target_compile_definitions(pivista-wizard-tests PRIVATE
        PIVISTA_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    )
    target_link_libraries(pivista-wizard-tests PRIVATE
        Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network Qt6::Test
    )
    add_test(NAME launcher-wizard COMMAND pivista-wizard-tests)

    add_executable(pivista-home-navigation-tests
        tests/test_home_navigation.cpp
        src/appcatalog.cpp
        src/appcatalog.h
        src/controlclient.cpp
        src/controlclient.h
        src/homecontrol.cpp
        src/homecontrol.h
    )
    target_include_directories(pivista-home-navigation-tests PRIVATE src)
    target_compile_definitions(pivista-home-navigation-tests PRIVATE
        PIVISTA_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
        PIVISTA_WEBAPP_CATALOG="${CMAKE_CURRENT_SOURCE_DIR}/../applications/web/catalog.json"
    )
    target_link_libraries(pivista-home-navigation-tests PRIVATE
        Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network Qt6::Test
    )
    add_test(NAME launcher-home-navigation COMMAND pivista-home-navigation-tests)
endif()
