// Telemetry blocking: an NSURLProtocol that answers the analytics endpoints itself instead of
// letting them out, and keeps a count of what it stopped for the Privacy page.
//
// Each SDK Spotify carries has somewhere of its own to send to: Firebase to app-measurement.com, the
// Facebook SDK to graph.facebook.com/<id>/activities, then Branch, Comscore, Segment. Nothing on the
// list carries playback, search, sign-in or deep links, which is why whole hosts are named where the
// host does nothing else and a path is named where it does.
//
// Spotify's own events, sent to spclient's /gabo-receiver-service/, are not on the list. They carry
// the playback reports Recents is built from: with them answered empty a track played never turned up
// in Recents, and it did with the block off (device 2026-09-21, issue #70).
//
// A protocol handed to +registerClass: is only consulted by NSURLConnection and the shared
// session, so both session configurations are given it as well: that is what the SDKs build their
// sessions from. What the core sends over its own sockets is out of reach either way, and the
// counters are what tell the two apart.
#import "Core/SGCore.h"
#import "Privacy.h"

typedef struct { const char *host, *path, *label; } SGBlockRule;

// host matched on the domain and its subdomains, path as a substring; no path means the whole host.
static const SGBlockRule kRules[] = {
    {"app-measurement.com",               NULL,                      "Firebase"},
    {"crashlytics.com",                   NULL,                      "Crashlytics"},
    {"facebook.com",                      "/activities",             "Facebook"},
    {"ep1.facebook.com",                  NULL,                      "Facebook"},
    {"ep2.facebook.com",                  NULL,                      "Facebook"},
    {"branch.io",                         "/v1/event",               "Branch"},
    {"scorecardresearch.com",             NULL,                      "Comscore"},
    {"segment.io",                        NULL,                      "Segment"},
    {"zqtk.net",                          NULL,                      "Segment"},
    {"google-analytics.com",              NULL,                      "Google"},
    {"googleadservices.com",              NULL,                      "Google"},
    {"doubleclick.net",                   NULL,                      "Google"},
};
static const size_t kRuleCount = sizeof(kRules) / sizeof(kRules[0]);

static NSString *const kCounts = @"spotifyglass.privacy.counts";
static NSMutableDictionary<NSString *, NSNumber *> *sg_counts;

@interface SGBlockProtocol : NSURLProtocol
@end

// The class object stands in for a lock: counting happens on whichever thread the request was made
// on, the Privacy page reads on the main one.
static NSMutableDictionary<NSString *, NSNumber *> *countsLocked(void) {
    if (!sg_counts) {
        sg_counts = [[NSUserDefaults.standardUserDefaults dictionaryForKey:kCounts] mutableCopy] ?: [NSMutableDictionary dictionary];
        // A count of a source that is not blocked any more (Spotify events, once) would stay in the total.
        NSArray<NSString *> *labels = SGBlockedLabels();
        for (NSString *label in sg_counts.allKeys) {
            if (![labels containsObject:label]) [sg_counts removeObjectForKey:label];
        }
    }
    return sg_counts;
}

static void countOne(NSString *label) {
    @synchronized (SGBlockProtocol.class) {
        NSMutableDictionary<NSString *, NSNumber *> *counts = countsLocked();
        counts[label] = @(counts[label].unsignedIntegerValue + 1);
        [NSUserDefaults.standardUserDefaults setObject:counts forKey:kCounts];
    }
}

static NSString *labelFor(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (!host) return nil;
    NSString *path = url.path ?: @"";
    for (size_t i = 0; i < kRuleCount; i++) {
        NSString *domain = @(kRules[i].host);
        if (![host isEqualToString:domain] && ![host hasSuffix:[@"." stringByAppendingString:domain]]) continue;
        if (kRules[i].path && ![path containsString:@(kRules[i].path)]) continue;
        return @(kRules[i].label);
    }
    return nil;
}

NSArray<NSString *> *SGBlockedLabels(void) {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (size_t i = 0; i < kRuleCount; i++) {
        NSString *label = @(kRules[i].label);
        if (![labels containsObject:label]) [labels addObject:label];
    }
    return labels;
}

NSUInteger SGBlockedCount(NSString *label) {
    @synchronized (SGBlockProtocol.class) {
        NSDictionary<NSString *, NSNumber *> *counts = countsLocked();
        if (label) return counts[label].unsignedIntegerValue;
        NSUInteger total = 0;
        for (NSNumber *count in counts.allValues) total += count.unsignedIntegerValue;
        return total;
    }
}

void SGResetBlocked(void) {
    @synchronized (SGBlockProtocol.class) {
        sg_counts = [NSMutableDictionary dictionary];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCounts];
    }
}

@implementation SGBlockProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return labelFor(request.URL) != nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *label = labelFor(self.request.URL);
    if (label) countOne(label);
    // 204 rather than an error: the sender takes it for delivered and queues no retry behind it.
    NSHTTPURLResponse *answer = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:204 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:answer cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end

static NSURLSessionConfiguration *carryingProtocol(NSURLSessionConfiguration *configuration) {
    if (!configuration || [configuration.protocolClasses containsObject:SGBlockProtocol.class]) return configuration;
    NSMutableArray *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
    [classes insertObject:SGBlockProtocol.class atIndex:0];
    configuration.protocolClasses = classes;
    return configuration;
}

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    return carryingProtocol(configuration);
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    return carryingProtocol(configuration);
}

%end

%ctor {
    if (SGEnabled(SGKeyBlockTelemetry)) {
        [NSURLProtocol registerClass:SGBlockProtocol.class];
        %init;
    }
}
