/*
 *
 *  Derived from CanDemo.pde, example code that came with the
 *  chipKIT Network Shield libraries.
 */

#include <stdint.h>
#include "chipKITCAN.h"
#include "chipKITUSBDevice.h"
#include "bitfield.h"
#include "canutil_chipkit.h"
#include "canwrite_chipkit.h"
#include "usbutil.h"
#include "cJSON.h"
#include "signals.h"
#include "handlers.h"

#define VERSION_CONTROL_COMMAND 0x80
#define RESET_CONTROL_COMMAND 0x81

// USB
#define DATA_ENDPOINT 1

char* VERSION = "2.0-pre";
CAN can1(CAN::CAN1);
CAN can2(CAN::CAN2);

// USB

#define DATA_ENDPOINT 1

USB_HANDLE USB_OUTPUT_HANDLE = 0;
CanUsbDevice usbDevice = {USBDevice(usbCallback), DATA_ENDPOINT, ENDPOINT_SIZE};

int receivedMessages = 0;
unsigned long lastSignificantChangeTime;
int receivedMessagesAtLastMark = 0;

// buffer messages up to 4x 1 USB packet in size waiting for valid JSON
const int PACKET_BUFFER_SIZE = ENDPOINT_SIZE * 4;
char PACKET_BUFFER[PACKET_BUFFER_SIZE];
int BUFFERED_PACKETS = 0;

/* Forward declarations */

void initializeAllCan();
void receiveCan(CanBus*);
void decodeCanMessage(int id, uint8_t* data);
void checkIfStalled();
void receiveWriteRequest(char*);

void setup() {
    Serial.begin(115200);

    initializeUsb(&usbDevice);
    initializeAllCan();
    lastSignificantChangeTime = millis();
}

void loop() {
    for(int i = 0; i < CAN_BUS_COUNT; i++) {
        receiveCan(&getCanBuses()[i]);
    }
    USB_OUTPUT_HANDLE = readFromHost(
            &usbDevice, USB_OUTPUT_HANDLE, &receiveWriteRequest);
    checkIfStalled();
}

void initializeAllCan() {
    for(int i = 0; i < CAN_BUS_COUNT; i++) {
        initializeCan(&(getCanBuses()[i]));
    }
}

void mark() {
    lastSignificantChangeTime = millis();
    receivedMessagesAtLastMark = receivedMessages;
}

void checkIfStalled() {
    // a workaround to stop CAN from crashing indefinitely
    // See these tickets in Redmine:
    // https://fiesta.eecs.umich.edu/issues/298
    // https://fiesta.eecs.umich.edu/issues/244
    if(receivedMessagesAtLastMark + 10 < receivedMessages) {
        mark();
    }

    if(receivedMessages > 0 && receivedMessagesAtLastMark > 0
            && millis() > lastSignificantChangeTime + 500) {
        initializeAllCan();
        delay(200);
        mark();
    }
}

/*
 * Thanks to https://gist.github.com/855214.
 */
const char *strnchr(const char *str, size_t len, int character) {
    const char *end = str + len;
    char c = (char)character;
    do {
        if(*str == c) {
            return str;
        }
    } while (++str <= end);
    return NULL;
}

void resetPacketBuffer() {
    BUFFERED_PACKETS = 0;
    memset(PACKET_BUFFER, 0, PACKET_BUFFER_SIZE);
}

void receiveWriteRequest(char* message) {
    if(message[0] != NULL) {
        strncpy((char*)(PACKET_BUFFER + (BUFFERED_PACKETS++ * ENDPOINT_SIZE)),
                message, ENDPOINT_SIZE);

        cJSON *root = cJSON_Parse(PACKET_BUFFER);
        if(root != NULL) {
            char* name = cJSON_GetObjectItem(root, "name")->valuestring;
            CanSignal* signal = lookupSignal(name, getSignals(),
                    getSignalCount());
            if(signal != NULL) {
                cJSON* value = cJSON_GetObjectItem(root, "value");
                CanCommand* command = lookupCommand(name, getCommands(),
                        getCommandCount());
                if(command != NULL) {
                    command->handler(name, value, getSignals(),
                            getSignalCount());
                } else {
                    sendCanSignal(signal, value, getSignals(),
                            getSignalCount());
                }
            } else {
                Serial.print("Writing not allowed for signal with name ");
                Serial.println(name);
            }
            cJSON_Delete(root);
            resetPacketBuffer();
        } else if(BUFFERED_PACKETS >= 4) {
            Serial.println("Incoming write is too long");
            resetPacketBuffer();
        } else if(strnchr(PACKET_BUFFER, ENDPOINT_SIZE * BUFFERED_PACKETS - 1,
                    NULL) != NULL) {
            Serial.println("Incoming buffered write is corrupted -- "
                    "clearing buffer");
            resetPacketBuffer();
        }
    }
}

/*
 * Check to see if a packet has been received. If so, read the packet and print
 * the packet payload to the serial monitor.
 */
void receiveCan(CanBus* bus) {
    CAN::RxMessageBuffer* message;

    if(bus->messageReceived == false) {
        // The flag is updated by the CAN ISR.
        return;
    }
    ++receivedMessages;

    message = bus->bus->getRxMessage(CAN::CHANNEL1);
    decodeCanMessage(message->msgSID.SID, message->data);

    /* Call the CAN::updateChannel() function to let the CAN module know that
     * the message processing is done. Enable the event so that the CAN module
     * generates an interrupt when the event occurs.*/
    bus->bus->updateChannel(CAN::CHANNEL1);
    bus->bus->enableChannelEvent(CAN::CHANNEL1, CAN::RX_CHANNEL_NOT_EMPTY,
            true);

    bus->messageReceived = false;
}

/* Called by the Interrupt Service Routine whenever an event we registered for
 * occurs - this is where we wake up and decide to process a message. */
void handleCan1Interrupt() {
    if((can1.getModuleEvent() & CAN::RX_EVENT) != 0) {
        if(can1.getPendingEventCode() == CAN::CHANNEL1_EVENT) {
            // Clear the event so we give up control of the CPU
            can1.enableChannelEvent(CAN::CHANNEL1,
                    CAN::RX_CHANNEL_NOT_EMPTY, false);
            getCanBuses()[0].messageReceived = true;
        }
    }
}

void handleCan2Interrupt() {
    if((can2.getModuleEvent() & CAN::RX_EVENT) != 0) {
        if(can2.getPendingEventCode() == CAN::CHANNEL1_EVENT) {
            // Clear the event so we give up control of the CPU
            can2.enableChannelEvent(CAN::CHANNEL1,
                    CAN::RX_CHANNEL_NOT_EMPTY, false);
            getCanBuses()[1].messageReceived = true;
        }
    }
}

static boolean customUSBCallback(USB_EVENT event, void* pdata, word size) {
    switch(SetupPkt.bRequest) {
    case VERSION_CONTROL_COMMAND:
        char combinedVersion[strlen(VERSION) + strlen(getMessageSet()) + 2];

        sprintf(combinedVersion, "%s (%s)", VERSION, getMessageSet());
        Serial.print("Version: ");
        Serial.println(combinedVersion);

        usbDevice.device.EP0SendRAMPtr((uint8_t*)combinedVersion,
                strlen(combinedVersion), USB_EP0_INCLUDE_ZERO);
        return true;
    case RESET_CONTROL_COMMAND:
        Serial.print("Resetting...");
        initializeAllCan();
        return true;
    default:
        return false;
    }
}

static boolean usbCallback(USB_EVENT event, void *pdata, word size) {
    // initial connection up to configure will be handled by the default
    // callback routine.
    usbDevice.device.DefaultCBEventHandler(event, pdata, size);

    switch(event) {
    case EVENT_CONFIGURED:
        Serial.println("Event: Configured");
        usbDevice.device.EnableEndpoint(DATA_ENDPOINT,
                USB_IN_ENABLED|USB_OUT_ENABLED|USB_HANDSHAKE_ENABLED|
                USB_DISALLOW_SETUP);
        armForRead(&usbDevice, usbDevice.receiveBuffer);
        break;

    case EVENT_EP0_REQUEST:
        if(!customUSBCallback(event, pdata, size)) {
            Serial.println("Event: Unrecognized EP0 (endpoint 0) Request");
        }
        break;

    default:
        break;
    }
}
