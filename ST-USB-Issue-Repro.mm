// clang -fobjc-arc -stdlib=libc++ -lstdc++ -std=c++17 -framework IOKit -o ST-USB-Issue-Repro ST-USB-Issue-Repro.mm
// ./ST-USB-Issue-Repro <vid> <pid>

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <string>
#import <vector>
#import <chrono>
#import <mach/mach_error.h>

static io_service_t _FindService(uint16_t vid, uint16_t pid) {
    NSMutableDictionary* dict = [(__bridge id)IOServiceMatching(kIOUSBDeviceClassName) mutableCopy];
    dict[@kUSBVendorID] = @(vid);
    dict[@kUSBProductID] = @(pid);
    CFRetain((__bridge CFTypeRef)dict); // Retain on behalf of IOServiceGetMatchingServices
    
    std::vector<io_service_t> services;
    io_iterator_t iter = MACH_PORT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(0, (__bridge CFDictionaryRef)dict, &iter);
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
    bool success = true;
    uintmax_t successCount = 0;
    try {
        if (argc != 3) {
            throw std::runtime_error(std::string("Usage: ") + argv[0] + " <vid> <pid>");
        }
        
        const uint16_t vid = std::stoi(argv[1]);
        const uint16_t pid = std::stoi(argv[2]);
        
        // Get service
        const io_service_t service = _FindService(vid, pid);
        IOUSBDeviceInterface**const usbDevice = _GetUSBDeviceInterface(service);
        
        for (;;) {
            constexpr uintmax_t RequestCount = 10000;
            auto timeStart = std::chrono::steady_clock::now();
            for (uintmax_t i=0; i<RequestCount; i++) @autoreleasepool {
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
                    throw std::runtime_error(std::string("ControlRequest failed: ") + mach_error_string(ior));
                }
                successCount++;
    //            printf("GetStatus control request succeeded (%ju)\n", i);
    //            return 0;
            }
            const std::chrono::microseconds durationUs = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - timeStart);
            printf("%.1f requests per second\n", ((float)RequestCount / durationUs.count()) * 1000000);
        }
    
    } catch (const std::exception& e) {
        system("say fail");
        // Ensure that the error gets printed after all our regular output,
        // in case stderr is redirected to stdout
        fflush(stdout);
        fprintf(stderr, "Error: %s\n", e.what());
        success = false;
    }
    
    printf("Successful control request count: %ju\n", successCount);
    return (success ? 0 : 1);
}
