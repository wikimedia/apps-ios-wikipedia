//  Created by Monte Hurd on 2/2/15.
//  Copyright (c) 2015 Wikimedia Foundation. Provided under MIT-style license; please copy and modify!

#import <UIKit/UIKit.h>

@interface UIFont (WMF_Style)

+ (UIFont*)wmf_glyphFontOfSize:(CGFloat)fontSize;

/// @return A copy of the receiver whose font size has been multiplied by @c scalar.
- (instancetype)wmf_copyWithSizeScaledBy:(CGFloat)scalar;

/// @return A copy of the receiver whose font size has been multipiled by `MENUS_SCALE_MULTIPLIER`.
- (instancetype)wmf_copyWithSizeScaledByMenuMultiplier;

@end
