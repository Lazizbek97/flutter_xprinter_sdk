#import "./include/flutter_xprinter_sdk/XprinterSdkPlugin.h"
#import "XprinterSdkManager.h"

static NSString *const kMethodChannel = @"dev.lazizbekfayziev.flutter_xprinter_sdk";
static NSString *const kDiscoveryChannel = @"dev.lazizbekfayziev.flutter_xprinter_sdk/discovery";

@interface XprinterSdkPlugin ()
@property (nonatomic, strong) XprinterSdkManager *manager;
@end

@implementation XprinterSdkPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *methodChannel =
        [FlutterMethodChannel methodChannelWithName:kMethodChannel
                                    binaryMessenger:[registrar messenger]];

    FlutterEventChannel *discoveryChannel =
        [FlutterEventChannel eventChannelWithName:kDiscoveryChannel
                                  binaryMessenger:[registrar messenger]];

    XprinterSdkPlugin *instance = [[XprinterSdkPlugin alloc] init];
    instance.manager = [[XprinterSdkManager alloc] init];

    [registrar addMethodCallDelegate:instance channel:methodChannel];
    [discoveryChannel setStreamHandler:instance.manager];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]]
        ? (NSDictionary *)call.arguments
        : @{};

    NSString *method = call.method;

    // Connection layer
    if ([method isEqualToString:@"connect"])     { [self.manager connect:args result:result]; return; }
    if ([method isEqualToString:@"disconnect"])  { [self.manager disconnect:result]; return; }
    if ([method isEqualToString:@"isConnected"]) { [self.manager isConnected:result]; return; }

    // Bluetooth scan / pair helpers
    if ([method isEqualToString:@"getBondedDevices"]) { [self.manager getBondedDevices:result]; return; }

    // Print methods
    if ([method isEqualToString:@"initialize"])           { [self.manager initialize:result]; return; }
    if ([method isEqualToString:@"printText"])            { [self.manager printText:args result:result]; return; }
    if ([method isEqualToString:@"printBitmap"])          { [self.manager printBitmap:args result:result]; return; }
    if ([method isEqualToString:@"printHorizontalLine"])  { [self.manager printHorizontalLine:args result:result]; return; }
    if ([method isEqualToString:@"printQRCode"])          { [self.manager printQRCode:args result:result]; return; }
    if ([method isEqualToString:@"printBarCode"])         { [self.manager printBarCode:args result:result]; return; }
    if ([method isEqualToString:@"feedLine"])             { [self.manager feedLine:args result:result]; return; }
    if ([method isEqualToString:@"cutPaper"])             { [self.manager cutPaper:args result:result]; return; }
    if ([method isEqualToString:@"selectCodePage"])       { [self.manager selectCodePage:args result:result]; return; }
    if ([method isEqualToString:@"setAlignment"])         { [self.manager setAlignment:args result:result]; return; }
    if ([method isEqualToString:@"getStatus"])            { [self.manager getStatus:result]; return; }
    if ([method isEqualToString:@"sendRawCommand"])       { [self.manager sendRawCommand:args result:result]; return; }

    result(FlutterMethodNotImplemented);
}

@end
