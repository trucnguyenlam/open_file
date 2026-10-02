#import "OpenFilePlugin.h"

@interface OpenFilePlugin ()<UIDocumentInteractionControllerDelegate>
@end

static NSString *const CHANNEL_NAME = @"open_file";

// Extends FlutterPluginRegistrar to expose viewController available on the
// concrete FlutterViewControllerRegistrar class used at runtime.
@protocol OpenFileFlutterPluginRegistrar <FlutterPluginRegistrar>
@property(nonatomic, readonly, weak) UIViewController *viewController;
@end

@implementation OpenFilePlugin{
    FlutterResult _result;
    UIDocumentInteractionController *_documentController;
    UIDocumentInteractionController *_interactionController;
    NSObject<OpenFileFlutterPluginRegistrar> *_registrar;
    BOOL _hasResponded;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:CHANNEL_NAME
                                     binaryMessenger:[registrar messenger]];
    OpenFilePlugin* instance = [[OpenFilePlugin alloc] initWithRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    self = [super init];
    if (self) {
        _registrar = (NSObject<OpenFileFlutterPluginRegistrar> *)registrar;
    }
    return self;
}

// Returns the root view controller using the registrar's viewController for
// UISceneDelegate compatibility (required for Flutter 3.38+ / iOS 26+).
// Falls back to scene enumeration for environments where the registrar does
// not expose viewController.
- (UIViewController *)rootViewController {
    // 1. Preferred: ask the Flutter registrar for the view controller
    if ([_registrar respondsToSelector:@selector(viewController)]) {
        UIViewController *vc = _registrar.viewController;
        if (vc != nil) {
            NSLog(@"[OpenFilePlugin] rootViewController from registrar: %@", vc);
            return vc;
        }
    }
    // 2. iOS 15+: use UIWindowScene.keyWindow (non-deprecated)
    if (@available(iOS 15, *)) {
        for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindow *keyWindow = ((UIWindowScene *)scene).keyWindow;
                if (keyWindow != nil) {
                    NSLog(@"[OpenFilePlugin] rootViewController from scene keyWindow: %@", keyWindow.rootViewController);
                    return keyWindow.rootViewController;
                }
            }
        }
        return nil;
    } else if (@available(iOS 13, *)) {
        // 3. iOS 13-14: iterate scene windows
        for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (window.isKeyWindow) {
                        NSLog(@"[OpenFilePlugin] rootViewController from scene window: %@", window.rootViewController);
                        return window.rootViewController;
                    }
                }
            }
        }
        return nil;
    } else {
        // 4. Pre-iOS 13 fallback
        return [UIApplication sharedApplication].delegate.window.rootViewController;
    }
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"open_file" isEqualToString:call.method]) {
        _result = result;
        _hasResponded = NO;
        NSString *msg = call.arguments[@"file_path"];
        if(msg==nil){
            NSDictionary * dict = @{@"message":@"the file path cannot be null", @"type":@-4};
            NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
            NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            _hasResponded = YES;
            result(json);
            return;
        }
        NSFileManager *fileManager=[NSFileManager defaultManager];
        BOOL fileExist=[fileManager fileExistsAtPath:msg];
        if(fileExist){
            NSLog(@"[OpenFilePlugin] File exists at path: %@", msg);
            _documentController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:msg]];
            _documentController.delegate = self;
            NSString *uti = call.arguments[@"uti"];
            BOOL isBlank = [self isBlankString:uti];
            if(!isBlank){
                _documentController.UTI = uti;
                NSLog(@"[OpenFilePlugin] Using provided UTI: %@", uti);
            } else {
                // Auto-detect UTI from file extension
                NSString *detectedUTI = [self utiForFileExtension:[[msg pathExtension] lowercaseString]];
                if (detectedUTI) {
                    _documentController.UTI = detectedUTI;
                    NSLog(@"[OpenFilePlugin] Auto-detected UTI: %@ for extension: %@", detectedUTI, [[msg pathExtension] lowercaseString]);
                } else {
                    NSLog(@"[OpenFilePlugin] No UTI provided or detected for extension: %@", [[msg pathExtension] lowercaseString]);
                }
            }
            @try {
                UIViewController *rootViewController = [self rootViewController];
                if (!rootViewController) {
                    NSLog(@"[OpenFilePlugin] ERROR: rootViewController is nil!");
                    NSDictionary * dict = @{@"message":@"the root view controller could not be found", @"type":@-4};
                    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
                    NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    _hasResponded = YES;
                    result(json);
                    return;
                }
                
                NSLog(@"[OpenFilePlugin] Attempting to present preview.");
                BOOL menuSucceeded = [_documentController presentPreviewAnimated:YES];
                if (!menuSucceeded) {
                    NSLog(@"[OpenFilePlugin] Preview failed, attempting to present open in menu from rect directly.");
                    menuSucceeded = [_documentController presentOpenInMenuFromRect:CGRectMake(rootViewController.view.bounds.size.width / 2, rootViewController.view.bounds.size.height / 2, 1, 1) inView:rootViewController.view animated:YES];
                }
                NSLog(@"[OpenFilePlugin] presentation result: %d", menuSucceeded);
                
                if (!menuSucceeded) {
                    NSLog(@"[OpenFilePlugin] No app found to open this file, returning error to Flutter.");
                    NSDictionary * dict = @{@"message":@"No app found to open this file", @"type":@-4};
                    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
                    NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    _hasResponded = YES;
                    result(json);
                } else {
                    NSLog(@"[OpenFilePlugin] Presentation succeeded, returning done to Flutter immediately.");
                    NSDictionary * dict2 = @{@"message":@"done", @"type":@0};
                    NSData * jsonData2 = [NSJSONSerialization dataWithJSONObject:dict2 options:NSJSONWritingPrettyPrinted error:nil];
                    NSString * json2 = [[NSString alloc] initWithData:jsonData2 encoding:NSUTF8StringEncoding];
                    _hasResponded = YES;
                    result(json2);
                }
            }@catch (NSException *exception) {
                NSLog(@"[OpenFilePlugin] Exception occurred: %@", exception);
                NSDictionary * dict = @{@"message":@"File opened incorrectly.", @"type":@-4};
                NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
                NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                if (!_hasResponded) {
                    _hasResponded = YES;
                    result(json);
                }
            }
        }else{
            NSDictionary * dict = @{@"message":@"the file does not exist", @"type":@-2};
            NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
            NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            if (!_hasResponded) {
                _hasResponded = YES;
                result(json);
            }
        }
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)documentInteractionControllerDidEndPreview:(UIDocumentInteractionController *)controller {
    if (!_hasResponded) {
        NSDictionary * dict = @{@"message":@"done", @"type":@0};
        NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
        NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        _hasResponded = YES;
        _result(json);
    }
}

- (void)documentInteractionControllerDidDismissOpenInMenu:(UIDocumentInteractionController *)controller {
    if (!_hasResponded) {
        NSDictionary * dict = @{@"message":@"done", @"type":@0};
        NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
        NSString * json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        _hasResponded = YES;
        _result(json);
    }
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return [self rootViewController];
}

- (NSString *)utiForFileExtension:(NSString *)ext {
    // Ebook formats
    if ([ext isEqualToString:@"epub"]) return @"org.idpf.epub-container";
    if ([ext isEqualToString:@"mobi"]) return @"com.amazon.mobi8-ebook";
    if ([ext isEqualToString:@"azw3"] || [ext isEqualToString:@"azw"]) return @"com.amazon.kindle.azw";
    if ([ext isEqualToString:@"cbz"]) return @"com.simplecomic.cbz-archive";
    if ([ext isEqualToString:@"cbr"]) return @"com.simplecomic.cbr-archive";
    if ([ext isEqualToString:@"fb2"]) return @"public.xml";
    if ([ext isEqualToString:@"djvu"] || [ext isEqualToString:@"djv"]) return @"image.djvu";
    // Document formats
    if ([ext isEqualToString:@"pdf"]) return @"com.adobe.pdf";
    if ([ext isEqualToString:@"rtf"]) return @"public.rtf";
    if ([ext isEqualToString:@"txt"]) return @"public.plain-text";
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return @"public.html";
    if ([ext isEqualToString:@"xml"]) return @"public.xml";
    if ([ext isEqualToString:@"doc"]) return @"com.microsoft.word.doc";
    if ([ext isEqualToString:@"docx"]) return @"org.openxmlformats.wordprocessingml.document";
    if ([ext isEqualToString:@"xls"]) return @"com.microsoft.excel.xls";
    if ([ext isEqualToString:@"xlsx"]) return @"org.openxmlformats.spreadsheetml.sheet";
    if ([ext isEqualToString:@"ppt"]) return @"com.microsoft.powerpoint.ppt";
    if ([ext isEqualToString:@"pptx"]) return @"org.openxmlformats.presentationml.presentation";
    // Image formats
    if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) return @"public.jpeg";
    if ([ext isEqualToString:@"png"]) return @"public.png";
    if ([ext isEqualToString:@"gif"]) return @"com.compuserve.gif";
    if ([ext isEqualToString:@"bmp"]) return @"com.microsoft.bmp";
    if ([ext isEqualToString:@"ico"]) return @"com.microsoft.ico";
    // Audio/Video formats
    if ([ext isEqualToString:@"mp3"]) return @"public.mp3";
    if ([ext isEqualToString:@"mp4"]) return @"public.mpeg-4";
    if ([ext isEqualToString:@"avi"]) return @"public.avi";
    if ([ext isEqualToString:@"mpg"] || [ext isEqualToString:@"mpeg"]) return @"public.mpeg";
    if ([ext isEqualToString:@"wav"]) return @"com.microsoft.waveform-audio";
    if ([ext isEqualToString:@"wmv"]) return @"com.microsoft.windows-media-wmv";
    // Archive formats
    if ([ext isEqualToString:@"zip"]) return @"com.pkware.zip-archive";
    if ([ext isEqualToString:@"tar"]) return @"public.tar-archive";
    if ([ext isEqualToString:@"gz"] || [ext isEqualToString:@"gzip"]) return @"org.gnu.gnu-zip-archive";
    if ([ext isEqualToString:@"tgz"]) return @"org.gnu.gnu-zip-tar-archive";
    return nil;
}

- (BOOL) isBlankString:(NSString *)string {
    if (string == nil || string == NULL) {
        return YES;
    }
    if ([string isKindOfClass:[NSNull class]]) {
        return YES;
    }
    if ([[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length]==0){
        return YES;
    }
    return NO;
}
@end
