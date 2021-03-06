//
//  VideoControlView.h
//  Clipster
//
//  Created by Anthony Sherbondy on 4/22/14.
//  Copyright (c) 2014 Nathan Speller. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface VideoControlView : UIView
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat currentPlaybackPosition;
@property (nonatomic, strong) NSArray *popularityHistogram;
@end
