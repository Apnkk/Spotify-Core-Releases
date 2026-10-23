// Local Files ID3v2 Tag & Artwork Editor (Edit Info: Title, Artist, Album, Cover Photo).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LocalFiles.h"
#import <PhotosUI/PhotosUI.h>

#pragma mark - ID3v2.3 Reader & Writer

@interface SGID3Metadata : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, strong) UIImage *artwork;
@end

@implementation SGID3Metadata
@end

static uint32_t readSynchsafe32(const uint8_t *b) {
    return ((uint32_t)(b[0] & 0x7F) << 21) |
           ((uint32_t)(b[1] & 0x7F) << 14) |
           ((uint32_t)(b[2] & 0x7F) << 7)  |
           ((uint32_t)(b[3] & 0x7F));
}

static void writeSynchsafe32(uint8_t *b, uint32_t val) {
    b[0] = (val >> 21) & 0x7F;
    b[1] = (val >> 14) & 0x7F;
    b[2] = (val >> 7)  & 0x7F;
    b[3] = val & 0x7F;
}

static uint32_t readBE32(const uint8_t *b) {
    return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
}

static void writeBE32(uint8_t *b, uint32_t val) {
    b[0] = (val >> 24) & 0xFF;
    b[1] = (val >> 16) & 0xFF;
    b[2] = (val >> 8)  & 0xFF;
    b[3] = val & 0xFF;
}

static NSString *decodeID3TextFrame(const uint8_t *payload, uint32_t len) {
    if (len < 2) return nil;
    uint8_t enc = payload[0];
    const uint8_t *bytes = payload + 1;
    uint32_t textLen = len - 1;
    NSString *s = nil;
    if (enc == 0) {
        s = [[NSString alloc] initWithBytes:bytes length:textLen encoding:NSISOLatin1StringEncoding];
    } else if (enc == 1) {
        s = [[NSString alloc] initWithBytes:bytes length:textLen encoding:NSUTF16StringEncoding];
    } else if (enc == 2) {
        s = [[NSString alloc] initWithBytes:bytes length:textLen encoding:NSUTF16BigEndianStringEncoding];
    } else {
        s = [[NSString alloc] initWithBytes:bytes length:textLen encoding:NSUTF8StringEncoding];
    }
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0 \t\r\n"]];
}

static SGID3Metadata *readID3Metadata(NSString *path) {
    SGID3Metadata *meta = [SGID3Metadata new];
    meta.title = [[path lastPathComponent] stringByDeletingPathExtension];
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < 10) return meta;
    const uint8_t *bytes = data.bytes;
    if (memcmp(bytes, "ID3", 3) != 0) return meta;

    uint8_t version = bytes[3];
    uint32_t tagSize = readSynchsafe32(bytes + 6);
    uint32_t end = MIN((uint32_t)data.length, 10 + tagSize);
    uint32_t pos = 10;

    while (pos + 10 <= end) {
        if (bytes[pos] == 0) break;
        char frameID[5] = { (char)bytes[pos], (char)bytes[pos+1], (char)bytes[pos+2], (char)bytes[pos+3], 0 };
        uint32_t frameSize = (version == 4) ? readSynchsafe32(bytes + pos + 4) : readBE32(bytes + pos + 4);
        pos += 10;
        if (frameSize == 0 || pos + frameSize > end) break;
        const uint8_t *payload = bytes + pos;
        if (strcmp(frameID, "TIT2") == 0) {
            NSString *v = decodeID3TextFrame(payload, frameSize);
            if (v.length) meta.title = v;
        } else if (strcmp(frameID, "TPE1") == 0) {
            NSString *v = decodeID3TextFrame(payload, frameSize);
            if (v.length) meta.artist = v;
        } else if (strcmp(frameID, "TALB") == 0) {
            NSString *v = decodeID3TextFrame(payload, frameSize);
            if (v.length) meta.album = v;
        } else if (strcmp(frameID, "APIC") == 0 && frameSize > 16) {
            // Find JPEG (FF D8) or PNG (89 50 4E 47) start inside APIC payload
            for (uint32_t i = 1; i + 4 < frameSize; i++) {
                if ((payload[i] == 0xFF && payload[i+1] == 0xD8) ||
                    (payload[i] == 0x89 && payload[i+1] == 0x50 && payload[i+2] == 0x4E && payload[i+3] == 0x47)) {
                    NSData *imgData = [NSData dataWithBytes:payload + i length:frameSize - i];
                    UIImage *img = [UIImage imageWithData:imgData];
                    if (img) meta.artwork = img;
                    break;
                }
            }
        }
        pos += frameSize;
    }
    return meta;
}

static void appendID3v23TextFrame(NSMutableData *frames, const char *frameID, NSString *text) {
    if (!text.length) return;
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8.length) return;
    uint32_t payloadSize = 1 + (uint32_t)utf8.length;
    uint8_t header[10] = {0};
    memcpy(header, frameID, 4);
    writeBE32(header + 4, payloadSize);
    [frames appendBytes:header length:10];
    uint8_t enc = 3; // UTF-8
    [frames appendBytes:&enc length:1];
    [frames appendData:utf8];
}

static void appendID3v23APICFrame(NSMutableData *frames, UIImage *image) {
    if (!image) return;
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.88);
    if (!jpeg.length) return;
    const char *mime = "image/jpeg";
    uint32_t mimeLen = (uint32_t)strlen(mime) + 1;
    uint32_t payloadSize = 1 + mimeLen + 1 + 1 + (uint32_t)jpeg.length;
    uint8_t header[10] = {0};
    memcpy(header, "APIC", 4);
    writeBE32(header + 4, payloadSize);
    [frames appendBytes:header length:10];
    uint8_t enc = 0;
    uint8_t picType = 3; // Front cover
    uint8_t descTerm = 0;
    [frames appendBytes:&enc length:1];
    [frames appendBytes:mime length:mimeLen];
    [frames appendBytes:&picType length:1];
    [frames appendBytes:&descTerm length:1];
    [frames appendData:jpeg];
}

static BOOL writeID3Metadata(NSString *path, SGID3Metadata *meta) {
    NSData *orig = [NSData dataWithContentsOfFile:path];
    if (!orig.length) return NO;
    const uint8_t *bytes = orig.bytes;
    uint32_t audioOffset = 0;
    if (orig.length >= 10 && memcmp(bytes, "ID3", 3) == 0) {
        uint32_t oldTagSize = readSynchsafe32(bytes + 6);
        audioOffset = MIN((uint32_t)orig.length, 10 + oldTagSize);
    }

    NSMutableData *frames = [NSMutableData data];
    appendID3v23TextFrame(frames, "TIT2", meta.title);
    appendID3v23TextFrame(frames, "TPE1", meta.artist);
    appendID3v23TextFrame(frames, "TALB", meta.album);
    appendID3v23APICFrame(frames, meta.artwork);

    uint8_t tagHeader[10] = { 'I', 'D', '3', 3, 0, 0, 0, 0, 0, 0 };
    writeSynchsafe32(tagHeader + 6, (uint32_t)frames.length);

    NSMutableData *outData = [NSMutableData dataWithCapacity:10 + frames.length + (orig.length - audioOffset)];
    [outData appendBytes:tagHeader length:10];
    [outData appendData:frames];
    [outData appendBytes:bytes + audioOffset length:orig.length - audioOffset];
    return [outData writeToFile:path atomically:YES];
}

#pragma mark - SGRLocalInfoEditor Sheet

@interface SGRLocalInfoEditor : UIViewController <PHPickerViewControllerDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) void (^onSaved)(void);
@end

@implementation SGRLocalInfoEditor {
    SGID3Metadata *_meta;
    UIImageView *_coverView;
    UITextField *_titleField;
    UITextField *_artistField;
    UITextField *_albumField;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Edit Info";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1.0];

    _meta = readID3Metadata(self.filePath);

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem.tintColor = SGGreen();

    _coverView = [UIImageView new];
    _coverView.contentMode = UIViewContentModeScaleAspectFill;
    _coverView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _coverView.layer.cornerRadius = 16;
    _coverView.clipsToBounds = YES;
    _coverView.image = _meta.artwork ?: [UIImage systemImageNamed:@"music.note"];
    _coverView.tintColor = SGGrey();
    _coverView.userInteractionEnabled = YES;
    _coverView.translatesAutoresizingMaskIntoConstraints = NO;
    [_coverView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickPhoto)]];
    [self.view addSubview:_coverView];

    UIButton *photoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [photoBtn setTitle:@"Choose Cover Photo…" forState:UIControlStateNormal];
    [photoBtn setTitleColor:SGGreen() forState:UIControlStateNormal];
    photoBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    photoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [photoBtn addTarget:self action:@selector(pickPhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:photoBtn];

    _titleField = [self makeFieldWithPlaceholder:@"Title" text:_meta.title];
    _artistField = [self makeFieldWithPlaceholder:@"Artist" text:_meta.artist];
    _albumField = [self makeFieldWithPlaceholder:@"Album" text:_meta.album];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleField, _artistField, _albumField]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_coverView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [_coverView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_coverView.widthAnchor constraintEqualToConstant:148],
        [_coverView.heightAnchor constraintEqualToConstant:148],
        [photoBtn.topAnchor constraintEqualToAnchor:_coverView.bottomAnchor constant:8],
        [photoBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.topAnchor constraintEqualToAnchor:photoBtn.bottomAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
    UITextField *tf = [UITextField new];
    tf.text = text;
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.35]
    }];
    tf.textColor = UIColor.whiteColor;
    tf.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    tf.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    tf.layer.cornerRadius = 12;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 44)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = self;
    [tf.heightAnchor constraintEqualToConstant:46].active = YES;
    return tf;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)pickPhoto {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [PHPickerConfiguration new];
        cfg.filter = [PHPickerFilter imagesFilter];
        cfg.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *res = results.firstObject;
    if (!res || ![res.itemProvider canLoadObjectOfClass:UIImage.class]) return;
    __weak typeof(self) weakSelf = self;
    [res.itemProvider loadObjectOfClass:UIImage.class completionHandler:^(__kindof id<NSItemProviderReading> object, NSError *error) {
        if ([object isKindOfClass:UIImage.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRLocalInfoEditor *strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf->_meta.artwork = (UIImage *)object;
                strongSelf->_coverView.image = (UIImage *)object;
            });
        }
    }];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
    _meta.title = _titleField.text;
    _meta.artist = _artistField.text;
    _meta.album = _albumField.text;
    writeID3Metadata(self.filePath, _meta);
    if (self.onSaved) self.onSaved();
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

void SGPresentLocalTrackEditorForPath(NSString *filePath, UIViewController *presenter, void (^onSaved)(void)) {
    if (!filePath.length || !presenter) return;
    SGRLocalInfoEditor *editor = [SGRLocalInfoEditor new];
    editor.filePath = filePath;
    editor.onSaved = onSaved;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = UIColor.whiteColor;
    [presenter presentViewController:nav animated:YES completion:nil];
}

static NSArray<NSString *> *discoverLocalMP3Files(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docs) return @[];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:docs];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *rel in enumerator) {
        if ([rel hasPrefix:@"spotifyglass/"]) continue;
        NSString *ext = rel.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"mp3"]) {
            [files addObject:[docs stringByAppendingPathComponent:rel]];
        }
    }
    return files;
}

UIViewController *SGLocalFilesEditorPage(void) {
    __weak __block SGModPage *weakPage = nil;
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Local files" build:^NSArray<SGModSection *> *{
        SGModRow *filesFlag = SGFlagRow(@"Local files from the Files app", @"enable_local_files_import");

        NSArray<NSString *> *mp3s = discoverLocalMP3Files();
        NSMutableArray<SGModRow *> *trackRows = [NSMutableArray array];
        for (NSString *path in mp3s) {
            SGID3Metadata *meta = readID3Metadata(path);
            NSString *title = meta.title.length ? meta.title : path.lastPathComponent;
            NSString *sub = meta.artist.length ? (meta.album.length ? [NSString stringWithFormat:@"%@ · %@", meta.artist, meta.album] : meta.artist) : path.lastPathComponent;
            SGModRow *row = SGActionRow(title, sub, ^{
                SGPresentLocalTrackEditorForPath(path, weakPage, ^{
                    [weakPage rebuild];
                });
            });
            if (meta.artwork) row.image = meta.artwork;
            else row = SGWithSymbol(row, @"music.note");
            [trackRows addObject:row];
        }
        if (!trackRows.count) {
            [trackRows addObject:SGStatRow(@"No .mp3 files found in Spotify Documents folder", ^NSString *{ return @""; })];
        }

        return @[
            SGNotedSection(nil, @[filesFlag], @"Tap any local .mp3 track below to edit its ID3v2 Title, Artist, Album, and embedded Cover Photo."),
            SGSection(@"Local MP3 Tracks", trackRows),
        ];
    }];
    weakPage = page;
    return page;
}
