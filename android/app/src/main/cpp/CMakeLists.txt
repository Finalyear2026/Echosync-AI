cmake_minimum_required(VERSION 3.22.1)

project("echosync_ai")

add_library(
    whisper_hardware_probe
    SHARED
    whisper_hardware_probe.cpp
)

find_library(log-lib log)

target_link_libraries(
    whisper_hardware_probe
    ${log-lib}
)