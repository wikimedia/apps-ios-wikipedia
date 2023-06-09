//
//  MWKLanguageLinkControllerTests.m
//  Wikipedia
//
//  Created by Brian Gerstle on 6/19/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "MWKLanguageLinkController_Private.h"
#import "MWKLanguageLink.h"
#import <OCHamcrest/OCHamcrest.h>

@interface MWKLanguageLinkControllerTests : XCTestCase
@property (strong, nonatomic) MWKLanguageLinkController* controller;
@end

@implementation MWKLanguageLinkControllerTests

- (void)setUp {
    [super setUp];

    NSAssert([[NSLocale preferredLanguages] containsObject:@"en"],
             @"For simplicity these tests assume the simulator has 'English' has one of its preferred languages.");

    // all tests must start w/ a clean slate
    WMFDeletePreviouslySelectedLanguages();
    [self instantiateController];
}

- (void)testReadPreviouslySelectedLanguagesReturnsEmpty {
    assertThat(WMFReadPreviouslySelectedLanguages(), hasCountOf(0));
}

- (void)testDefaultsToDevicePreferredLanguages {
    NSParameterAssert(self.controller.filteredPreferredLanguageCodes.count > 0);

    /*
       using weaker "intersection" test since there might be a case where the sim preferred languages have
       more than what's defined in the static language data
     */
    XCTAssertTrue([[NSSet setWithArray:self.controller.filteredPreferredLanguageCodes]
                   intersectsSet:
                   [NSSet setWithArray:[NSLocale preferredLanguages]]]);

    [self verifyAllLanguageArrayProperties];
}

- (void)testSaveSelectedLanguageUpdatesTheControllersFilteredPreferredLanguages {
    NSAssert(![self.controller.filteredPreferredLanguageCodes containsObject:@"test"],
             @"'test' shouldn't be a default member of preferred languages!");

    [self.controller saveSelectedLanguageCode:@"test"];

    assertThat(self.controller.filteredPreferredLanguageCodes, hasItem(@"test"));
    [self verifyAllLanguageArrayProperties];
}

- (void)testUniqueAppendToPreferredLanguages {
    [self.controller saveSelectedLanguageCode:@"test"];
    NSArray* firstAppend = [self.controller.filteredOtherLanguages copy];

    [self.controller saveSelectedLanguageCode:@"test"];
    NSArray* secondAppend = [self.controller.filteredOtherLanguages copy];

    assertThat(firstAppend, is(equalTo(secondAppend)));

    [self verifyAllLanguageArrayProperties];
}

- (void)testPersistentSaves {
    id firstController = self.controller;
    [firstController saveSelectedLanguageCode:@"test"];
    [self instantiateController];
    NSParameterAssert(firstController != self.controller);
    assertThat(self.controller.filteredPreferredLanguageCodes, hasItem(@"test"));
}

#pragma mark - Utils

- (void)instantiateController {
    self.controller = [MWKLanguageLinkController new];
    // temporarily repurpose static lang data for testing
    [self.controller loadStaticSiteLanguageData];
}

- (void)verifyAllLanguageArrayProperties {
    [self verifyPreferredAndOtherSumIsAllLanguages];
    [self verifyPreferredAndOtherAreDisjoint];
}

- (void)verifyPreferredAndOtherAreDisjoint {
    XCTAssertFalse([[NSSet setWithArray:self.controller.filteredPreferredLanguages]
                    intersectsSet:
                    [NSSet setWithArray:self.controller.filteredOtherLanguages]],
                   @"'preferred' and 'other' languages shouldn't intersect: \n preferred: %@ \nother: %@",
                   self.controller.filteredPreferredLanguages, self.controller.filteredOtherLanguages);
}

- (void)verifyPreferredAndOtherSumIsAllLanguages {
    NSSet* joinedLanguages = [NSSet setWithArray:
                              [self.controller.filteredPreferredLanguages
                               arrayByAddingObjectsFromArray:self.controller.filteredOtherLanguages]];

    assertThat(joinedLanguages,
               hasCountOf(self.controller.filteredOtherLanguages.count
                          + self.controller.filteredPreferredLanguages.count));

    assertThat([NSSet setWithArray:self.controller.languageLinks], is(equalTo(joinedLanguages)));
}

@end
