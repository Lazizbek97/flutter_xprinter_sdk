# The Flutter tooling requires CMake 3.14 or later for Windows plugins.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flutter_xprinter_sdk")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "flutter_xprinter_sdk_plugin")

list(APPEND PLUGIN_SOURCES
  "xprinter_sdk_plugin.cpp"
  "xprinter_sdk_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/flutter_xprinter_sdk/xprinter_sdk_plugin_c_api.h"
  "xprinter_sdk_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(XPRINTER_WINDOWS_SDK_DLL
  "${CMAKE_CURRENT_SOURCE_DIR}/xprinter_sdk/x64/printer.sdk.dll")

if(NOT EXISTS "${XPRINTER_WINDOWS_SDK_DLL}")
  message(FATAL_ERROR
    "Bundled XPrinter Windows SDK not found at "
    "${XPRINTER_WINDOWS_SDK_DLL}.")
endif()

set(flutter_xprinter_sdk_bundled_libraries
  "${XPRINTER_WINDOWS_SDK_DLL}"
  PARENT_SCOPE
)
