//
//  MWKLanguageLinkController.m
//  Wikipedia
//
//  Created by Brian Gerstle on 6/17/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.
//

#import "MWKLanguageLinkController_Private.h"
#import "MWKTitle.h"
#import "MWKLanguageLink.h"
#import "MWKLanguageLinkFetcher.h"
#import "NSObjectUtilities.h"
#import "QueuesSingleton.h"
#import "SessionSingleton.h"
#import "NSString+Extras.h"

#import "Defines.h"
#import "WMFAssetsFile.h"

#import <BlocksKit/BlocksKit.h>

NS_ASSUME_NONNULL_BEGIN

static NSString* const WMFPreviousLanguagesKey = @"WMFPreviousSelectedLanguagesKey";

void WMFDeletePreviouslySelectedLanguages() {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:WMFPreviousLanguagesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

NSArray* WMFReadPreviouslySelectedLanguages() {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:WMFPreviousLanguagesKey] ? : @[];
}

/// Get the union of OS preferred languages & previously selected languages.
static NSArray* WMFReadPreviousAndPreferredLanguages() {
    NSMutableSet* preferredLanguages = [NSMutableSet setWithArray:[NSLocale preferredLanguages]];
    [preferredLanguages addObjectsFromArray:WMFReadPreviouslySelectedLanguages()];
    return [preferredLanguages allObjects];
}

/// Uniquely append @c languageCode to the list of previously selected languages.
static NSArray* WMFAppendAndWriteToPreviousLanguages(NSString* languageCode) {
    NSMutableArray* langCodes = WMFReadPreviouslySelectedLanguages().mutableCopy;
    if (![langCodes containsObject:languageCode]) {
        [langCodes addObject:languageCode];
        [[NSUserDefaults standardUserDefaults] setObject:langCodes forKey:WMFPreviousLanguagesKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return langCodes;
}

/**
 * List of unsupported language codes.
 *
 * As of iOS 8, the system font doesn't support these languages, e.g. "arc" (Aramaic, Syriac font). [0]
 *
 * 0: http://syriaca.org/documentation/view-syriac.html
 */
static NSArray* WMFUnsupportedLanguages() {
    static NSArray* unsupportedLanguageCodes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unsupportedLanguageCodes = @[@"my", @"am", @"km", @"dv", @"lez", @"arc", @"got", @"ti"];;
    });
    return unsupportedLanguageCodes;
}

@interface MWKLanguageLinkController ()

@property (readonly, strong, nonatomic) MWKLanguageLinkFetcher* fetcher;

@property (readwrite, copy, nonatomic) NSArray* filteredPreferredLanguages;

@property (readwrite, copy, nonatomic) NSArray* filteredOtherLanguages;

@end

@implementation MWKLanguageLinkController
@synthesize languageFilter = _languageFilter;
@synthesize fetcher        = _fetcher;

- (void)loadStaticSiteLanguageData {
    WMFAssetsFile* assetsFile = [[WMFAssetsFile alloc] initWithFileType:WMFAssetsFileTypeLanguages];
    self.languageLinks = [assetsFile.array bk_map:^id (NSDictionary* langAsset) {
        return [[MWKLanguageLink alloc] initWithLanguageCode:langAsset[@"code"]
                                               pageTitleText:@""
                                                        name:langAsset[@"name"]
                                               localizedName:langAsset[@"canonical_name"]];
    }];
    [self updateFilteredLanguages];
}

#pragma mark - Loading

- (MWKLanguageLinkFetcher*)fetcher {
    if (!_fetcher) {
        _fetcher = [[MWKLanguageLinkFetcher alloc] initWithManager:[[QueuesSingleton sharedInstance] languageLinksFetcher]
                                                          delegate:nil];
    }
    return _fetcher;
}

- (void)loadLanguagesForTitle:(MWKTitle*)title
                      success:(dispatch_block_t)success
                      failure:(void (^ __nullable)(NSError* __nonnull))failure {
    [[QueuesSingleton sharedInstance].languageLinksFetcher.operationQueue cancelAllOperations];
    [self.fetcher fetchLanguageLinksForTitle:[SessionSingleton sharedInstance].currentArticle.title
                                     success:^(NSArray* languageLinks) {
        self.languageLinks = languageLinks;
        [self updateFilteredLanguages];
        if (success) {
            success();
        }
    }
                                     failure:failure];
}

#pragma mark - Getters & Setters

- (NSArray*)languageCodes {
    return [self.languageLinks valueForKey:WMF_SAFE_KEYPATH(MWKLanguageLink.new, languageCode)];
}

- (NSArray*)filteredPreferredLanguageCodes {
    return [self.filteredPreferredLanguages valueForKey:WMF_SAFE_KEYPATH(MWKLanguageLink.new, languageCode)];
}

- (void)setLanguageFilter:(NSString* __nullable)filterString {
    if (WMF_EQUAL(self.languageFilter, isEqualToString:, filterString)) {
        return;
    }
    _languageFilter = [filterString copy];
    [self updateFilteredLanguages];
}

- (NSArray*)sortedAndFilteredLanguageLinks {
    return [[self filteredLanguageLinks] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray*)filteredLanguageLinks {
    if (self.languageFilter.length) {
        return [self.languageLinks bk_select:^BOOL (MWKLanguageLink* langLink) {
            return [langLink.name wmf_caseInsensitiveContainsString:self.languageFilter]
            || [langLink.localizedName wmf_caseInsensitiveContainsString:self.languageFilter];
        }];
    } else {
        return self.languageLinks;
    }
}

- (void)setLanguageLinks:(NSArray* __nonnull)languageLinks {
    NSArray* unsupportedLanguages   = WMFUnsupportedLanguages();
    NSArray* supportedLanguageLinks = [languageLinks bk_reject:^BOOL (MWKLanguageLink* languageLink) {
        return [unsupportedLanguages containsObject:languageLink.languageCode];
    }];
    if (WMF_EQUAL(self.languageLinks, isEqualToArray:, languageLinks)) {
        return;
    }
    [self willChangeValueForKey:WMF_SAFE_KEYPATH(self, languageLinks)];
    _languageLinks = supportedLanguageLinks;
    [self updateFilteredLanguages];
    [self didChangeValueForKey:WMF_SAFE_KEYPATH(self, languageLinks)];
}

- (void)updateFilteredLanguages {
    [self updateFilteredLanguagesWithPreviousLanguages:WMFReadPreviousAndPreferredLanguages()];
}

- (void)updateFilteredLanguagesWithPreviousLanguages:(NSArray*)previousLanguages {
    NSArray* sortedAndFilteredLanguages = [self sortedAndFilteredLanguageLinks];
    NSArray* preferredLangs             = WMFReadPreviousAndPreferredLanguages();
    self.filteredPreferredLanguages = [sortedAndFilteredLanguages bk_select:^BOOL (MWKLanguageLink* langLink) {
        return [preferredLangs containsObject:langLink.languageCode];
    }];
    self.filteredOtherLanguages = [sortedAndFilteredLanguages bk_select:^BOOL (MWKLanguageLink* langLink) {
        return ![self.filteredPreferredLanguages containsObject:langLink];
    }];
}

#pragma mark - Saving

- (void)saveSelectedLanguage:(MWKLanguageLink*)language {
    [self saveSelectedLanguageCode:language.languageCode];
}

- (void)saveSelectedLanguageCode:(NSString*)languageCode {
    [self updateFilteredLanguagesWithPreviousLanguages:WMFAppendAndWriteToPreviousLanguages(languageCode)];
}

@end

NS_ASSUME_NONNULL_END
