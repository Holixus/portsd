cmake_minimum_required(VERSION 2.6)

PROJECT(portsd)

OPTION(HOST_DEBUG "Log to console" OFF)

ADD_DEFINITIONS(-pipe --std=gnu99 -ftabstop=4 -Wno-unused-function)
ADD_DEFINITIONS(-Wall -Wmissing-declarations -Winit-self -Wswitch-enum -Wundef -Wshadow)
ADD_DEFINITIONS(-Wmissing-field-initializers -Wredundant-decls -Wpointer-arith)

ADD_DEFINITIONS(-D_GNU_SOURCE)

FILE(GLOB SOURCES *.c nano/*.c)

ADD_EXECUTABLE(${CMAKE_PROJECT_NAME} ${SOURCES})

IF(HOST_DEBUG)
	ADD_DEFINITIONS(-O0 -g3)
ELSE()
	ADD_DEFINITIONS(-Os -Werror -fvisibility=hidden -ffast-math -fmerge-all-constants -ffunction-sections -fdata-sections)
	SET_TARGET_PROPERTIES(${CMAKE_PROJECT_NAME} PROPERTIES LINK_FLAGS -Wl,--gc-sections,-s)
ENDIF()


INSTALL(TARGETS ${CMAKE_PROJECT_NAME}
	ARCHIVE DESTINATION lib
	LIBRARY DESTINATION lib
	RUNTIME DESTINATION bin
)
