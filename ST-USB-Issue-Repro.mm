#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <vector>

constexpr uint16_t VID = 51966;
constexpr uint16_t PID = 16384;

static io_service_t _FindService() {
    NSMutableDictionary* dict = [(__bridge id)IOServiceMatching(kIOUSBDeviceClassName) mutableCopy];
    dict[@kUSBVendorID] = @(VID);
    dict[@kUSBProductID] = @(PID);
    CFRetain((__bridge CFTypeRef)dict); // Retain on behalf of IOServiceGetMatchingServices
    
    std::vector<io_service_t> services;
    io_iterator_t iter = MACH_PORT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (__bridge CFDictionaryRef)dict, &iter);
    if (kr != kIOReturnSuccess) {
        throw std::runtime_error("IOServiceGetMatchingServices failed");
    }
    
    for (;;) {
        io_service_t service = IOIteratorNext(iter);
        if (service == MACH_PORT_NULL) break;
        services.push_back(service);
    }
    
    if (services.size() == 0) {
        throw std::runtime_error("no matching devices");
    } else if (services.size() > 1) {
        throw std::runtime_error("too many matching devices");
    }
    
    return services[0];
}

static IOUSBDeviceInterface** _GetUSBDeviceInterface(io_service_t service) {
    IOCFPlugInInterface** plugin = nullptr;
    SInt32 score = 0;
    IOReturn kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
    if (!plugin) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
    
    IOUSBDeviceInterface** iface = nullptr;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&iface);
    if (hr) throw std::runtime_error("QueryInterface failed");
    return iface;
}

int main(int argc, const char* argv[]) {
    
    try {
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    // Get service
    io_service_t service = _FindService();
    IOUSBDeviceInterface** usbDevice = _GetUSBDeviceInterface(service);
    
    for (;;) {
        uint8_t status[2];
        IOUSBDevRequest req = {
            .bmRequestType  = USBmakebmRequestType(kUSBIn, kUSBStandard, kUSBDevice),
            .bRequest       = kUSBRqGetStatus,
            .wValue         = 0,
            .wIndex         = 0,
            .wLength        = 2,
            .pData          = status,
        };
        
        IOReturn ior = (*usbDevice)->DeviceRequest(usbDevice, &req);
        if (ior != kIOReturnSuccess) {
            throw std::runtime_error("ControlRequest failed");
        }
        printf("GetStatus control request succeeded\n");
    }
    
    return 0;
}
