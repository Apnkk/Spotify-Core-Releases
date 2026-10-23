#import <UIKit/UIKit.h>

#define SGKeyStats @"spotifyglass.stats"

BOOL SGStatsEnabled(void);
NSString *SGStatsSummary(void);
UIViewController *SGStatsDashboardPage(void);
UIViewController *SGStatsSettingsPage(void);
