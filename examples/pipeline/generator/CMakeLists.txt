cmake_minimum_required(VERSION 3.8)
project(generator)

set(CMAKE_CXX_STANDARD 14)

include_directories(/usr/local/include include)

set(SOURCE_FILES main.cpp)
add_executable(generator ${SOURCE_FILES})
