cmake_minimum_required(VERSION 3.15)
project(AsgardMultiFileDemo C)

set(CMAKE_C_STANDARD 11)
include_directories(include)

# Standard Target Definition
set(SOURCES
    src/license.c
    src/crypto.c
    src/auth.c
    src/main.c
)

# Custom Target invoking ASGARD Project Builder
add_custom_target(asgard_protect ALL
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/../../random_visa project -d ${CMAKE_CURRENT_SOURCE_DIR}/src -o ${CMAKE_CURRENT_BINARY_DIR}/secure_app --cff --mba -s 42
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building Hardened Binary via ASGARD-5877 VM Protector..."
)
