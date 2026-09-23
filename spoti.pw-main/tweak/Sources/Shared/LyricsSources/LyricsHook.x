// Spotify's /color-lyrics/v2/track/<id> answered with the chain's lyrics, in the URLSession delegates
// Spotify reads the reply through, SPTDataLoaderService and HttpClientURLSession, the way
// EeveeSpotify Reincarnated answers it on 9.1 (DataLoaderServiceHooks.x.swift). Three cases:
//
// Spotify has lyrics of its own (a 200). The body is read in whole and handed on with the chain's
// lines in place of Spotify's when they are timed, on the main queue, which 9.1.60 and later require
// of these callbacks. This is the path that is known to put the lyrics card under the player.
//
// Spotify's own metadata says the track has none. Its request is sent to a donor track instead, one
// that has lyrics everywhere, and the 200 that comes back has its lines swapped for the chain's as
// above: a 404 turned into a 200 in the delegate alone never showed a card on 9.1.78, however fast
// it came, while a real 200 with our lines in it always did. The donor's own lines are never shown:
// with nothing from the chain the request is failed as Spotify's would have been. The player-track
// hook below notes what the metadata said, and forces has_lyrics on so the request is made at all.
//
// A 404 for a track the metadata has not been seen for. The reply is held where it arrives, its
// completion handler with it, until the chain has answered; the delegate is then told of a 200, the
// lyrics and the end, and the task's own response answers the same 200, since Spotify's client may
// read the status from either. Spotify's real 404 body that follows is dropped, so the task is
// answered exactly once.
//
// Whichever lines win go to the karaoke page as well, and the source that supplied them is credited
// there.
//
// None of that shows a card on its own. The cards under the player are a list the server sends per
// track, scrollsita's NpvScrollResponse, and it holds a lyrics section only for tracks Spotify has
// lyrics for; the lyrics provider is asked for a track only when its section is in the list. So the
// list is read on the way in and a lyrics section is put at its top for any track without one that
// a source may have lyrics for. The section's shape is copied from the last list that carried one,
// with the track's own URI inside; before any has passed, it is the URI alone. The player then asks
// for the lyrics as it would for any track, and the reply is answered as above.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "Shared/Lyrics/Protobuf.h"
#import "Headers/SPTPlayer.h"

// Blinding Lights, The Weeknd: lyrics in every market Spotify serves them in.
static NSString *const kDonorTrack = @"0VjIjW4GlUZAMYd2vXMi3b";
// On a request sent to the donor: the track it was made for.
static NSString *const kTrackProperty = @"spotifyglass.lyricsTrack";
static NSString *const kLyricsPath = @"/color-lyrics/v2/track/";
// NpvScrollResponse { 1 structure: { 1 repeated section: Section { oneof section_type: 5 lyrics: { 1 entity_uri } } } }
// The oneof's cases, in the order Spotify declares them: comments, creator_bio, discovery_feed,
// credits, lyrics, merch and on, which is the order proto fields are numbered in.
static const uint32_t kStructureField = 1, kSectionField = 1, kLyricsSectionField = 5, kEntityURIField = 1;
// The page's colours when Spotify sent none to keep, ARGB.
static const uint32_t kBackground = 0xFF535353, kLine = 0xFF000000, kActiveLine = 0xFFFFFFFF;

static NSString *trackInURL(NSURL *url) {
    NSString *path = url.path;
    NSRange marker = [path rangeOfString:kLyricsPath];
    if (marker.location == NSNotFound) return nil;
    NSString *track = [[path substringFromIndex:NSMaxRange(marker)] componentsSeparatedByString:@"/"].firstObject;
    return track.length ? track : nil;
}

// The track a request was made for: the one it was sent to the donor for, else the one in its URL.
static NSString *trackFor(NSURLRequest *request) {
    id kept = [NSURLProtocol propertyForKey:kTrackProperty inRequest:request];
    return [kept isKindOfClass:NSString.class] ? kept : trackInURL(request.URL);
}

static NSString *trackOf(NSURLSessionTask *task) {
    return trackFor(task.originalRequest) ?: trackFor(task.currentRequest);
}

static BOOL sentToDonor(NSURLSessionTask *task) {
    return [NSURLProtocol propertyForKey:kTrackProperty inRequest:task.originalRequest] != nil
        || [NSURLProtocol propertyForKey:kTrackProperty inRequest:task.currentRequest] != nil;
}

static NSInteger statusOf(NSURLResponse *response) {
    return [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
}

// Lyrics { 1 data: { 1 time_synchronized, 2 repeated line { 1 offset_ms, 2 content }, 5 provided_by },
//          2 colors { 1 background, 2 line, 3 active_line } }
static NSData *lyricsBody(SGLyricsResult *lyrics, NSData *spotify) {
    NSMutableArray<SGPBField *> *data = [NSMutableArray array];
    if (lyrics.synced) [data addObject:SGPBVarint(1, 1)];
    for (NSUInteger i = 0; i < lyrics.texts.count; i++) {
        NSData *line = SGPBSerialize(@[SGPBVarint(1, (uint64_t)MAX(lyrics.starts[i].integerValue, 0)), SGPBString(2, lyrics.texts[i])]);
        [data addObject:SGPBBytes(2, line)];
    }
    [data addObject:SGPBString(5, lyrics.provider ?: @"Musixmatch")];
    SGPBField *colors = SGPBFirst(SGPBParse(spotify), 2);
    if (colors.wire != 2) colors = SGPBBytes(2, SGPBSerialize(@[SGPBVarint(1, kBackground), SGPBVarint(2, kLine), SGPBVarint(3, kActiveLine)]));
    return SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(data)), colors]);
}

// The chain's body, or nil to hand Spotify's reply on as it came. `spotify` is Spotify's own 200
// body when it has one; a donor's carries no lines of the track's and only lends its colours, and
// only when the server made them from the track's own artwork, which it names in the URL.
static NSData *chosenBody(NSString *track, SGLyricsResult *lyrics, NSData *spotify, BOOL donor, BOOL donorColors) {
    NSArray<SGKaraokeLine *> *spotifyLines = donor ? nil : SGKaraokeLinesFromBody(spotify);
    SGKaraokeTiming spotifyTiming = SGKaraokeLinesTiming(spotifyLines);
    // Spotify's own page keeps its own lines when they are timed and the chain's are not.
    BOOL ours = lyrics.texts.count && (lyrics.synced || spotifyTiming == SGKaraokeTimingNone);
    // The lyrics view takes the more finely timed of the two, the chain's on a tie.
    BOOL oursFiner = lyrics.karaokeLines.count && (!spotifyLines || SGKaraokeLinesTiming(lyrics.karaokeLines) <= spotifyTiming);
    NSArray<SGKaraokeLine *> *karaoke = oursFiner ? lyrics.karaokeLines : spotifyLines;
    if (karaoke) SGKaraokeKeepLines(track, karaoke);
    SGLyricsSetCredit(track, karaoke == lyrics.karaokeLines ? lyrics.provider : @"Spotify");
    // Plain text for the view while Spotify has lyrics of its own: its JSON may still have them timed.
    if (!donor && spotify.length && SGKaraokeLinesTiming(karaoke) == SGKaraokeTimingNone) SGKaraokeAskSpotifyForTiming(track);
    SGLog(@"lyrics: page of %@ gets %@; the lyrics view %@'s, %@", track, ours ? [NSString stringWithFormat:@"%@'s lines", lyrics.provider] : spotifyLines ? @"Spotify's own lines" : @"no lyrics",
          oursFiner ? lyrics.provider : @"Spotify", SGKaraokeLinesTiming(karaoke) == SGKaraokeTimingWords ? @"word timed"
          : SGKaraokeLinesTiming(karaoke) == SGKaraokeTimingLine ? @"line timed" : @"untimed");
    return ours ? lyricsBody(lyrics, donor && !donorColors ? nil : spotify) : nil;
}

#pragma mark - the card list, given a lyrics section

// The track a scrollsita request is for: .../scrollsita/v1/scroll/spotify:track:<id>, the URI
// escaped or not.
static NSString *scrollTrackOf(NSURLSessionTask *task) {
    NSURL *url = task.currentRequest.URL ?: task.originalRequest.URL;
    NSString *path = url.path;
    if (![path containsString:@"/scrollsita/"]) return nil;
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        NSString *piece = part.stringByRemovingPercentEncoding ?: part;
        if ([piece hasPrefix:@"spotify:track:"]) {
            NSString *track = [piece substringFromIndex:@"spotify:track:".length];
            return track.length ? track : nil;
        }
    }
    return nil;
}

// The last lyrics section the server sent, whole, so an added one has every field the client may
// want beyond the URI. Any thread, under its lock.
static NSData *sg_lyricsSectionTemplate;
static NSObject *sg_templateLock;

static NSData *lyricsSectionFor(NSString *track) {
    NSString *uri = [@"spotify:track:" stringByAppendingString:track];
    NSData *lyrics = SGPBSerialize(@[SGPBString(kEntityURIField, uri)]);
    NSData *template;
    @synchronized (sg_templateLock) { template = sg_lyricsSectionTemplate; }
    NSMutableArray<SGPBField *> *fields = template ? SGPBParse(template) : nil;
    if (!fields) return SGPBSerialize(@[SGPBBytes(kLyricsSectionField, lyrics)]);
    for (SGPBField *field in fields) {
        if (field.number == kLyricsSectionField) field.payload = lyrics;
    }
    return SGPBSerialize(fields);
}

// The list with a lyrics section at its top, or nil to hand it on as it came: it has one, or the
// track is one no source has lyrics for, or the bytes are not what they should be.
static NSData *listWithLyrics(NSData *body, NSString *track) {
    NSMutableArray<SGPBField *> *fields = SGPBParse(body);
    SGPBField *structure = SGPBFirst(fields, kStructureField);
    if (structure.wire != 2) {
        SGLog(@"scrollsita: list for %@ not read, %lu bytes", track, (unsigned long)body.length);
        return nil;
    }
    NSMutableArray<SGPBField *> *sections = SGPBParse(structure.payload);
    for (SGPBField *section in sections) {
        if (section.number != kSectionField || section.wire != 2) continue;
        SGPBField *kind = SGPBParse(section.payload).firstObject;
        if (kind.number == kLyricsSectionField && kind.wire == 2) {
            @synchronized (sg_templateLock) { sg_lyricsSectionTemplate = section.payload; }
            return nil;
        }
    }
    if (!SGLyricsMayHave(track)) return nil;
    SGPBField *added = SGPBBytes(kSectionField, lyricsSectionFor(track));
    NSMutableArray<SGPBField *> *withLyrics = [NSMutableArray arrayWithObject:added];
    [withLyrics addObjectsFromArray:sections];
    structure.payload = SGPBSerialize(withLyrics);
    SGLog(@"scrollsita: lyrics section added to the card list of %@", track);
    return SGPBSerialize(fields);
}

#pragma mark - the request, sent to the donor when Spotify has nothing

// The same request for the donor track, or nil to let this one go as it is: Spotify has lyrics for
// the track, or has not said yet, or every source has already said it has none, or the mod made it.
static NSURLRequest *donorRequest(NSURLRequest *request) {
    if (!request.URL || [NSURLProtocol propertyForKey:SGLyricsOwnRequestKey inRequest:request]) return nil;
    if ([NSURLProtocol propertyForKey:kTrackProperty inRequest:request]) return nil;
    NSString *track = trackInURL(request.URL);
    if (!track || [track isEqualToString:kDonorTrack]) return nil;
    if (SGLyricsSpotifyHas(track) != 0 || !SGLyricsMayHave(track)) return nil;
    NSString *absolute = request.URL.absoluteString;
    NSRange marker = [absolute rangeOfString:[kLyricsPath stringByAppendingString:track]];
    if (marker.location == NSNotFound) return nil;
    NSRange idRange = NSMakeRange(NSMaxRange(marker) - track.length, track.length);
    NSURL *url = [NSURL URLWithString:[absolute stringByReplacingCharactersInRange:idRange withString:kDonorTrack]];
    if (!url) return nil;
    NSMutableURLRequest *donor = [request mutableCopy];
    donor.URL = url;
    [NSURLProtocol setProperty:track forKey:kTrackProperty inRequest:donor];
    SGLog(@"lyrics: Spotify has none for %@, its request goes to the donor", track);
    SGLyricsPrefetch(track);
    return donor;
}

%group Sessions
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLRequest *donor = donorRequest(request);
    return %orig(donor ?: request);
}
%end
%end

// The sessions Spotify makes are __NSURLSessionLocal; hooked as well only when that class answers
// dataTaskWithRequest: itself, since a hook on an inherited method would sit on NSURLSession's twice.
%group LocalSessions
%hook __NSURLSessionLocal
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLRequest *donor = donorRequest(request);
    return %orig(donor ?: request);
}
%end
%end

#pragma mark - the reply

// What the hook knows of one lyrics task it answers. The delegate hears of a task on Spotify's own
// queue and of the answer on the main queue, so everything here is read and written under its lock.
@interface SGLyricsTask : NSObject
@property (nonatomic, copy) NSString *track;
@property (nonatomic) BOOL scroll;        // a card list, not lyrics: read in whole and given its section
@property (nonatomic) BOOL donor;         // the request went to the donor; the 200 is not the track's
@property (nonatomic) BOOL donorColors;   // and the server coloured it from the track's own artwork
@property (nonatomic) BOOL held;          // Spotify's server said no; the reply is the chain's
@property (nonatomic) BOOL answered;      // the 200 and the lyrics went out
@property (nonatomic) BOOL gone;          // the task ended before the lyrics were in
@property (nonatomic, strong) NSHTTPURLResponse *fake;   // the 200 the task itself answers with
@property (nonatomic, strong) NSMutableData *buffer;     // Spotify's own 200, read in whole
@property (nonatomic, strong) NSData *ours;              // the body handed on, let through by identity
@end

@implementation SGLyricsTask
@end

static char kTaskKey;

static SGLyricsTask *stateOf(NSURLSessionTask *task) {
    return objc_getAssociatedObject(task, &kTaskKey);
}

// A held task's own -response answers with the 200 the delegate was told of. The class that
// implements -response is found from the first held task, so every task of it goes through here;
// one not held answers as before.
static IMP sg_origResponse;

static id ownResponse(id self, SEL _cmd) {
    SGLyricsTask *state = stateOf(self);
    NSHTTPURLResponse *fake = nil;
    if (state) {
        @synchronized (state) { fake = state.fake; }
    }
    return fake ?: ((id (*)(id, SEL))sg_origResponse)(self, _cmd);
}

static void answerResponseOf(NSURLSessionTask *task) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL selector = @selector(response);
        Class owner = object_getClass(task);
        while (owner) {
            unsigned count = 0;
            Method *methods = class_copyMethodList(owner, &count);
            BOOL found = NO;
            for (unsigned i = 0; i < count && !found; i++) found = method_getName(methods[i]) == selector;
            free(methods);
            if (found) break;
            owner = class_getSuperclass(owner);
        }
        Method method = class_getInstanceMethod(owner ?: object_getClass(task), selector);
        if (!method) return;
        sg_origResponse = method_setImplementation(method, (IMP)ownResponse);
        SGLog(@"lyrics: -response of %@ answers for held tasks", NSStringFromClass(owner ?: object_getClass(task)));
    });
}

// The body goes to the delegate as any data would, through every hook on the way, and the hook here
// knows it by the very object it handed over.
static void handOn(id delegate, NSURLSession *session, NSURLSessionTask *task, SGLyricsTask *state, NSData *body) {
    @synchronized (state) { state.ours = body; }
    [delegate URLSession:session dataTask:(NSURLSessionDataTask *)task didReceiveData:body];
}

static NSHTTPURLResponse *okFor(NSURL *url, NSData *body) {
    return [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/2.0"
                                     headerFields:@{@"Content-Type": @"application/protobuf", @"Content-Length": @(body.length).stringValue}];
}

static NSError *noLyricsError(void) {
    return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled
                           userInfo:@{NSLocalizedDescriptionKey: @"no lyrics for this track from any source"}];
}

typedef void (^SGDisposition)(NSURLSessionResponseDisposition);

// The response callback. `orig` hands a response and a completion handler on to Spotify's delegate.
static void onResponse(id delegate, NSURLSession *session, NSURLSessionDataTask *task, NSURLResponse *response,
                       SGDisposition handler, void (^orig)(NSURLResponse *, SGDisposition)) {
    if (stateOf(task)) {
        orig(response, handler);
        return;
    }
    NSString *scroll = scrollTrackOf(task);
    if (scroll) {
        if (statusOf(response) == 200) {
            SGLyricsTask *state = [SGLyricsTask new];
            state.track = scroll;
            state.scroll = YES;
            state.buffer = [NSMutableData data];
            objc_setAssociatedObject(task, &kTaskKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        orig(response, handler);
        return;
    }
    NSString *track = trackOf(task);
    if (!track) {
        orig(response, handler);
        return;
    }
    SGLyricsTask *state = [SGLyricsTask new];
    state.track = track;
    state.donor = sentToDonor(task);
    state.donorColors = state.donor && [task.currentRequest.URL.path containsString:@"/image/"];
    objc_setAssociatedObject(task, &kTaskKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSInteger status = statusOf(response);
    SGLog(@"lyrics: Spotify answered %ld for %@%@", (long)status, track, state.donor ? @" through the donor" : @"");
    if (status == 200) {
        @synchronized (state) { state.buffer = [NSMutableData data]; }
        orig(response, handler);
        return;
    }
    @synchronized (state) { state.held = YES; }
    dispatch_async(dispatch_get_main_queue(), ^{
        SGLyricsFetch(track, ^(SGLyricsResult *lyrics) {
            @synchronized (state) {
                if (state.gone) return;
            }
            NSData *body = chosenBody(track, lyrics, nil, NO, NO);
            if (!body) {
                @synchronized (state) { state.held = NO; }
                orig(response, handler);
                return;
            }
            // Spotify decides on the 200 with a handler of the hook's; the real one is only called once
            // the lyrics are with the delegate, so the 404 body the server still sends comes after them
            // and is dropped.
            __block BOOL decided = NO, delivered = NO;
            __block NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
            SGDisposition decide = ^(NSURLSessionResponseDisposition chosen) {
                BOOL now;
                @synchronized (state) {
                    decided = YES;
                    disposition = chosen;
                    now = delivered;
                }
                if (now) handler(chosen);
            };
            NSHTTPURLResponse *ok = okFor(task.currentRequest.URL, body);
            answerResponseOf(task);
            @synchronized (state) {
                state.fake = ok;
                state.answered = YES;
            }
            orig(ok, decide);
            handOn(delegate, session, task, state, body);
            BOOL now;
            @synchronized (state) {
                delivered = YES;
                now = decided;
            }
            if (now) handler(disposition);
        });
    });
}

// The data callback: YES when the data goes on to Spotify's delegate.
static BOOL onData(NSURLSessionTask *task, NSData *data) {
    SGLyricsTask *state = stateOf(task);
    if (!state) return YES;
    @synchronized (state) {
        if (data == state.ours) {
            state.ours = nil;
            return YES;
        }
        if (state.held && state.answered) return NO;   // Spotify's own 404 body, after the chain's lyrics
        if (state.buffer) {
            [state.buffer appendData:data];
            return NO;
        }
    }
    return YES;
}

// The completion callback. `orig` ends the task at Spotify's delegate.
static void onComplete(id delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error, void (^orig)(NSError *)) {
    SGLyricsTask *state = stateOf(task);
    NSData *spotify = nil;
    if (state) {
        @synchronized (state) {
            if (state.held && !state.answered) state.gone = YES;
            if (state.buffer && !error) spotify = [state.buffer copy];
            state.buffer = nil;
        }
    }
    if (!spotify) {
        orig(error);
        return;
    }
    NSString *track = state.track;
    if (state.scroll) {
        handOn(delegate, session, task, state, listWithLyrics(spotify, track) ?: spotify);
        orig(nil);
        return;
    }
    BOOL json = spotify.length && ((const uint8_t *)spotify.bytes)[0] == '{';
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^finish)(NSData *) = ^(NSData *body) {
            handOn(delegate, session, task, state, body);
            orig(nil);
        };
        if (json && !state.donor) {
            finish(spotify);
            return;
        }
        SGLyricsFetch(track, ^(SGLyricsResult *lyrics) {
            NSData *body = chosenBody(track, lyrics, spotify, state.donor, state.donorColors);
            if (body) {
                finish(body);
                return;
            }
            if (!state.donor) {
                finish(spotify);
                return;
            }
            // Nothing from anyone: the donor's lines must not show for the track, so the request
            // fails as Spotify's own would have.
            SGLog(@"lyrics: no lyrics for %@ from any source, its request fails as Spotify's did", track);
            orig(noLyricsError());
        });
    });
}

%group Delegates
%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(SGDisposition)handler {
    onResponse(self, session, task, response, handler, ^(NSURLResponse *passed, SGDisposition decide) { %orig(session, task, passed, decide); });
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (onData(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    onComplete(self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(SGDisposition)handler {
    onResponse(self, session, task, response, handler, ^(NSURLResponse *passed, SGDisposition decide) { %orig(session, task, passed, decide); });
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (onData(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    onComplete(self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end
%end

#pragma mark - the track

// The player offers the lyrics card by the track's has_lyrics. What Spotify's metadata said is
// noted first, since it is what sends the request to the donor, and the track is remembered so the
// chain has its name before the player reports it.
%group AllTracks
// What the metadata is answered with: has_lyrics on for a track a source may have lyrics for.
static NSDictionary *markedMetadata(SPTPlayerTrack *self, NSDictionary *metadata) {
    BOOL has = [metadata[@"has_lyrics"] isEqual:@"true"];
    id uri = self.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? [(NSURL *)uri absoluteString] : [uri description];
    if (![text hasPrefix:@"spotify:track:"]) return metadata;
    NSString *track = [text substringFromIndex:@"spotify:track:".length];
    SGLyricsNoteSpotifyHas(track, has);
    SGKaraokeRememberTrack(self);
    if (has || !SGLyricsMayHave(track)) return metadata;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"lyrics: marking tracks without Spotify lyrics as having some, first %@", text); });
    NSMutableDictionary *marked = [metadata mutableCopy] ?: [NSMutableDictionary dictionary];
    marked[@"has_lyrics"] = @"true";
    return marked;
}

%hook SPTPlayerTrack
- (NSDictionary *)metadata {
    NSDictionary *metadata = %orig;
    return markedMetadata(self, metadata);
}
%end
%end

%ctor {
    SGLyricsMigrateLegacyKeys();
    if (!SGLyricsEnabled()) return;
    sg_templateLock = [NSObject new];
    %init(Delegates);
    BOOL allTracks = SGFlag(SGKeyLyricsAllTracks, NO);
    if (allTracks) {
        %init(AllTracks);
        %init(Sessions);
        SEL selector = @selector(dataTaskWithRequest:);
        Class local = objc_getClass("__NSURLSessionLocal");
        Method own = local ? class_getInstanceMethod(local, selector) : NULL;
        if (own && own != class_getInstanceMethod(NSURLSession.class, selector)) %init(LocalSessions);
    }
    SGLog(@"lyrics: sources %@, every track %@", [SGLyricsOrder() componentsJoinedByString:@", "], allTracks ? @"on" : @"off");
    SGRequireClasses(@[@"SPTPlayerTrack", @"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession"]);
}
