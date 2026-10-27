cmake_minimum_required(VERSION 3.15)
project(asgard_ida_plugin CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Default to local IDA SDK location
set(IDA_SDK_DIR "/Users/password9090/Desktop/test/ida-sdk" CACHE PATH "Path to IDA Pro SDK")

if (NOT EXISTS "${IDA_SDK_DIR}/src/include/ida.hpp")
    message(FATAL_ERROR "IDA SDK not found at ${IDA_SDK_DIR}. Please specify -DIDA_SDK_DIR=<path>")
endif()

include_directories(
    ${IDA_SDK_DIR}/src/include
)

add_library(asgard_ida_plugin MODULE
    src/asgard_ida_plugin.cpp
)

set_target_properties(asgard_ida_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "asgard_ida_plugin"
)

if (APPLE)
    set_target_properties(asgard_ida_plugin PROPERTIES
        SUFFIX ".dylib"
    )
elseif (UNIX)
    set_target_properties(asgard_ida_plugin PROPERTIES
        SUFFIX ".so"
    )
endif()

# Platform-specific definitions for IDA 9 SDK
target_compile_definitions(asgard_ida_plugin PRIVATE
    __IDP__
    __PLUGIN__
)

if (APPLE)
    target_compile_definitions(asgard_ida_plugin PRIVATE __MAC__)
elseif (UNIX)
    target_compile_definitions(asgard_ida_plugin PRIVATE __LINUX__)
endif()
