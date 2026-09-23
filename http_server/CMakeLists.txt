cmake_minimum_required(VERSION 3.10)
project(HTTPSERVER ASM)

set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS} -nostdlib")

add_executable(http_server http_server.s)
