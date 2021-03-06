BOARD_TAG = mega_pic32
TARGET = $(BASE_TARGET)-pic32

ARDUINO_LIBS = chipKITUSBDevice chipKITUSBDevice/utility cJSON
ifdef ETHERNET
ARDUINO_LIBS += chipKITEthernet chipKITEthernet/utility
endif

ifndef CAN_EMULATOR
ARDUINO_LIBS += chipKITCAN
endif

NO_CORE_MAIN_FUNCTION = 1
SKIP_SUFFIX_CHECK = 1
OBJDIR = build/pic32

SERIAL_BAUDRATE = 115200

OSTYPE := $(shell uname)

ifndef ARDUINO_PORT
	ifeq ($(OSTYPE),Darwin)
		ARDUINO_PORT = /dev/tty.usbserial*
	else
		ARDUINO_PORT = /dev/ttyUSB*
	endif
endif

EXTRA_CPPFLAGS += -G0 -D__PIC32__ $(CC_SYMBOLS)

CHIPKIT_LIBRARY_AGREEMENT_URL = http://www.digilentinc.com/Agreement.cfm?DocID=DSD-0000318

EXPECTED_USB_LIBRARY_PATH = ./libs/chipKITUSBDevice
MICROCHIP_USB_LIBRARY_EXISTS = $(shell test -d $(EXPECTED_USB_LIBRARY_PATH); echo $$?)
ifneq ($(MICROCHIP_USB_LIBRARY_EXISTS),0)
$(error chipKIT USB device library missing - download separately from $(CHIPKIT_LIBRARY_AGREEMENT_URL) and place at $(EXPECTED_USB_LIBRARY_PATH))
endif

ifndef CAN_EMULATOR
EXPECTED_CAN_LIBRARY_PATH = ./libs/chipKITCAN
MICROCHIP_CAN_LIBRARY_EXISTS = $(shell test -d $(EXPECTED_CAN_LIBRARY_PATH); echo $$?)
ifneq ($(MICROCHIP_CAN_LIBRARY_EXISTS),0)
$(error chipKIT CAN library missing - download separately from $(CHIPKIT_LIBRARY_AGREEMENT_URL) and place at $(EXPECTED_CAN_LIBRARY_PATH))
endif
endif

ifdef ETHERNET
EXPECTED_ETHERNET_LIBRARY_PATH = ./libs/chipKITEthernet
MICROCHIP_ETHERNET_LIBRARY_EXISTS = $(shell test -d $(EXPECTED_ETHERNET_LIBRARY_PATH); echo $$?)
ifneq ($(MICROCHIP_ETHERNET_LIBRARY_EXISTS),0)
$(error chipKIT Ethernet library missing - download separately from $(CHIPKIT_LIBRARY_AGREEMENT_URL) and place at $(EXPECTED_ETHERNET_LIBRARY_PATH))
endif
endif

ARDUINO_MK_EXISTS = $(shell test -e libs/arduino.mk/chipKIT.mk; echo $$?)
ifneq ($(ARDUINO_MK_EXISTS),0)
$(error arduino.mk library missing - did you run "git submodule init && git submodule update"?)
endif

USER_LIB_PATH = ./libs
ARDUINO_MAKEFILE_HOME = libs/arduino.mk

LOCAL_C_SRCS += $(wildcard pic32/*.c)
LOCAL_CPP_SRCS += $(wildcard pic32/*.cpp)

include $(ARDUINO_MAKEFILE_HOME)/chipKIT.mk

flash: upload
