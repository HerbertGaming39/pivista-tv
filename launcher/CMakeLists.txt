cmake_minimum_required(VERSION 3.16)
project(pivista-launcher VERSION 0.1.0 LANGUAGES CXX)

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
endif()
