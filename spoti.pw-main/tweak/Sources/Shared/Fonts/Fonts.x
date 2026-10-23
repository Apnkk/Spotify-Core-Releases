// Custom Font picker & .ttf/.otf/.ttc importer via CoreText.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Fonts.h"
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *sg_loadedCustomFamily;

static NSString *fontsDirectory(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"spotifyglass/fonts"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static void registerSavedCustomFont(void) {
    NSString *fileName = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyFontCustomFile];
    if (!fileName.length) return;
    NSString *fullPath = [fontsDirectory() stringByAppendingPathComponent:fileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:fullPath]) return;
    NSURL *url = [NSURL fileURLWithPath:fullPath];
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
    CFArrayRef descs = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (descs) {
        if (CFArrayGetCount(descs) > 0) {
            CTFontDescriptorRef desc = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descs, 0);
            CFStringRef fam = (CFStringRef)CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute);
            if (fam) {
                sg_loadedCustomFamily = [(__bridge NSString *)fam copy];
                CFRelease(fam);
            }
        }
        CFRelease(descs);
    }
    if (!sg_loadedCustomFamily.length) {
        sg_loadedCustomFamily = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyFontCustomName];
    }
}

static UIFontWeight approximateWeightFromFont(UIFont *font) {
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    NSNumber *w = traits[UIFontWeightTrait];
    if (w) return (UIFontWeight)w.doubleValue;
    NSString *name = font.fontName.lowercaseString;
    if ([name containsString:@"black"] || [name containsString:@"heavy"]) return UIFontWeightHeavy;
    if ([name containsString:@"bold"]) return UIFontWeightBold;
    if ([name containsString:@"semibold"] || [name containsString:@"demi"]) return UIFontWeightSemibold;
    if ([name containsString:@"medium"]) return UIFontWeightMedium;
    if ([name containsString:@"light"]) return UIFontWeightLight;
    return UIFontWeightRegular;
}

UIFont *SGTransformFontIfNeeded(UIFont *font) {
    if (!font) return nil;
    NSInteger mode = SGInt(SGKeyFont, 0); // 0=Default, 1=Rounded, 2=Serif, 3=Monospaced, 4=Custom
    if (mode == 0) return font;

    CGFloat size = font.pointSize;
    UIFontWeight weight = approximateWeightFromFont(font);

    if (mode == 4) {
        NSString *family = sg_loadedCustomFamily ?: [NSUserDefaults.standardUserDefaults stringForKey:SGKeyFontCustomName];
        if (family.length) {
            UIFontDescriptor *base = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
                UIFontDescriptorFamilyAttribute: family,
                UIFontDescriptorTraitsAttribute: @{ UIFontWeightTrait: @(weight) }
            }];
            UIFont *custom = [UIFont fontWithDescriptor:base size:size];
            if (custom) return custom;
        }
        return font;
    }

    UIFontDescriptorSystemDesign design = UIFontDescriptorSystemDesignDefault;
    if (mode == 1) design = UIFontDescriptorSystemDesignRounded;
    else if (mode == 2) design = UIFontDescriptorSystemDesignSerif;
    else if (mode == 3) design = UIFontDescriptorSystemDesignMonospaced;

    UIFont *sys = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *desc = [sys.fontDescriptor fontDescriptorWithDesign:design];
    return desc ? [UIFont fontWithDescriptor:desc size:size] : sys;
}

%hook UILabel
- (void)setFont:(UIFont *)font {
    %orig(SGTransformFontIfNeeded(font));
}
%end

#pragma mark - Font Picker Document Delegate

@interface SGFontPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) SGModPage *page;
@end

@implementation SGFontPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL sec = [url startAccessingSecurityScopedResource];
    NSString *fileName = url.lastPathComponent ?: @"custom_font.ttf";
    NSString *destPath = [fontsDirectory() stringByAppendingPathComponent:fileName];
    [NSFileManager.defaultManager removeItemAtPath:destPath error:nil];
    [[NSData dataWithContentsOfURL:url] writeToFile:destPath atomically:YES];
    if (sec) [url stopAccessingSecurityScopedResource];

    NSURL *destURL = [NSURL fileURLWithPath:destPath];
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)destURL, kCTFontManagerScopeProcess, NULL);
    NSString *familyName = [fileName stringByDeletingPathExtension];
    CFArrayRef descs = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)destURL);
    if (descs) {
        if (CFArrayGetCount(descs) > 0) {
            CTFontDescriptorRef desc = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descs, 0);
            CFStringRef fam = (CFStringRef)CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute);
            if (fam) {
                familyName = [(__bridge NSString *)fam copy];
                CFRelease(fam);
            }
        }
        CFRelease(descs);
    }
    sg_loadedCustomFamily = familyName;
    [NSUserDefaults.standardUserDefaults setObject:fileName forKey:SGKeyFontCustomFile];
    [NSUserDefaults.standardUserDefaults setObject:familyName forKey:SGKeyFontCustomName];
    SGSetInt(SGKeyFont, 4);
    [self.page rebuild];
}

@end

static SGFontPickerDelegate *sg_fontPickerDelegate;

NSString *SGFontSummary(void) {
    NSInteger mode = SGInt(SGKeyFont, 0);
    switch (mode) {
        case 1: return @"Rounded";
        case 2: return @"Serif";
        case 3: return @"Monospaced";
        case 4: return [NSUserDefaults.standardUserDefaults stringForKey:SGKeyFontCustomName] ?: @"Custom";
        default: return @"Default";
    }
}

UIViewController *SGFontSettingsPage(void) {
    __weak __block SGModPage *weakPage = nil;
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Font" build:^NSArray<SGModSection *> *{
        NSString *customName = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyFontCustomName];
        NSArray<NSString *> *choices = @[
            @"Spotify Default",
            @"SF Rounded",
            @"New York (Serif)",
            @"SF Mono",
            customName.length ? [NSString stringWithFormat:@"Custom (%@)", customName] : @"Custom font file"
        ];
        SGModRow *styleRow = SGWithSymbol(SGChoiceRow(@"Typeface", nil, SGKeyFont, choices, 0), @"textformat");
        styleRow.choiceNotes = @[
            @"Spotify Circular / system default typeface",
            @"Apple's rounded system typeface across all screens",
            @"Apple's New York editorial serif typeface",
            @"Apple's monospaced developer typeface",
            @"Your imported .ttf, .otf or .ttc font file"
        ];

        SGModRow *importRow = SGWithSymbol(SGActionRow(@"Import font file…", @"Choose a .ttf, .otf, or .ttc file from the Files app", ^{
            sg_fontPickerDelegate = [SGFontPickerDelegate new];
            sg_fontPickerDelegate.page = weakPage;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFont] asCopy:YES];
            picker.delegate = sg_fontPickerDelegate;
            [weakPage presentViewController:picker animated:YES completion:nil];
        }), @"doc.badge.plus");

        return @[
            SGNotedSection(nil, @[styleRow, importRow], @"Applies across labels, titles, and lyrics immediately as screens load."),
        ];
    }];
    weakPage = page;
    return page;
}

%ctor {
    registerSavedCustomFont();
    %init;
}
