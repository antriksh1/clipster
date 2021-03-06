//
//  ClippingViewController.m
//  Clipster
//
//  Created by Nathan Speller on 4/18/14.
//  Copyright (c) 2014 Nathan Speller. All rights reserved.
//

#import "ClippingViewController.h"
#import "RulerView.h"
#import "RPFloatingPlaceholderTextView.h"
#import "ClipsterColors.h"

@interface ClippingViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *startSlider;
@property (weak, nonatomic) IBOutlet UIImageView *endSlider;
@property (weak, nonatomic) IBOutlet UIImageView *sliderWindow;
@property (nonatomic, assign) CGPoint startPosition;
@property (nonatomic, assign) CGPoint   endPosition;
@property (weak, nonatomic) IBOutlet UIView *rulerContainer;
@property (strong, nonatomic) RulerView *rulerView;
@property (nonatomic, assign) CGFloat startTime;
@property (nonatomic, assign) CGFloat   endTime;
@property (nonatomic, assign) CGFloat startTimeIntermediate;
@property (nonatomic, assign) CGFloat   endTimeIntermediate;
@property (weak, nonatomic) IBOutlet UILabel *startTimeLabel;
@property (weak, nonatomic) IBOutlet UILabel *endTimeLabel;
@property (nonatomic, assign) CGFloat translation;
@property (weak, nonatomic) IBOutlet UIView *videoPlayerContainer;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (nonatomic, strong) Clip *clip;
@property (weak, nonatomic) IBOutlet RPFloatingPlaceholderTextView *annotationTextView;
@property (nonatomic, strong) VideoPlayerViewController *playerController;
@property (weak, nonatomic) IBOutlet UIView *navBar;
@property (weak, nonatomic) IBOutlet UIButton *doneButton;
@property (weak, nonatomic) IBOutlet UIButton *cancelButton;

// current playback stuff
@property (nonatomic, strong) id timeObserverHandle;
@property (nonatomic, strong) UIView *playbackProgressView;
@property (nonatomic, assign) CGFloat currentPlaybackPosition;

@end

@implementation ClippingViewController

static CGFloat startSliderHomePos = 50;
static CGFloat   endSliderHomePos = 240;

- (id)init
{
    self = [super init];
    if (self) {
        self.title = @"Clipping";
    }
    return self;
}

- (id)initWithClip:(Clip*)clip playerController:(VideoPlayerViewController*)playerController
{
    self = [self init];
    if (self) {
        _clip = clip;
        _playerController = playerController;
        _playerController.isLooping = YES;
    }
    return self;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // done is only enabled once we have a description
    self.doneButton.enabled = NO;
    self.doneButton.titleLabel.textColor = [UIColor lightGrayColor];
    
    self.annotationTextView.delegate = self;
    self.annotationTextView.placeholder = @"Enter Description";
    
    
    if ([self respondsToSelector:@selector(edgesForExtendedLayout)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    // Add pan gestures to draggable sliders
    UIPanGestureRecognizer *startPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onStartSliderDrag:)];
    [self.startSlider addGestureRecognizer:startPanGestureRecognizer];
    
    UIPanGestureRecognizer *endPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onEndSliderDrag:)];
    [self.endSlider addGestureRecognizer:endPanGestureRecognizer];
    
    // Draw the ruler
    self.rulerView = [[RulerView alloc] initWithFrame:CGRectMake(0, 0, self.rulerContainer.frame.size.width, self.rulerContainer.frame.size.height)];
    [self.rulerContainer addSubview:self.rulerView];
    self.startTime = self.clip.timeStart / 1000.0f;
    self.endTime = self.clip.timeEnd / 1000.0f;
    [self updateRulerData:self.rulerView];
    
    // Draw the playback progress
    self.playbackProgressView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, self.rulerContainer.frame.size.height)];
    self.playbackProgressView.backgroundColor = [[ClipsterColors red] colorWithAlphaComponent:0.5];
    [self.rulerContainer addSubview:self.playbackProgressView];
    self.currentPlaybackPosition = 0;

    // add the player to ourself
    [self.playerController.view setFrame: self.videoPlayerContainer.frame];
    [self.videoPlayerContainer addSubview: self.playerController.view];
    
    // start the playback monitor
    [self startMonitorPlaybackTimer];
}

#pragma mark - Keyboard / Description Text
- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self.scrollView setContentOffset:self.rulerContainer.frame.origin animated:YES];
}

- (void)textViewDidChange:(UITextView *)textView
{
    BOOL enableDone = textView.text && textView.text.length > 0;
    self.doneButton.enabled = enableDone;
    if (!enableDone) {
        self.doneButton.titleLabel.textColor = [UIColor lightGrayColor];
    }
}

- (IBAction)tapAction:(id)sender
{
    if (self.annotationTextView.isFirstResponder) {
        [self.annotationTextView resignFirstResponder];
    }
    [self.scrollView setContentOffset:self.videoPlayerContainer.frame.origin animated:YES];
}

#pragma mark - Call delegate
- (IBAction)doneAction:(id)sender
{
    [self stopMonitorPlaybackTimer];
    self.clip.text = self.annotationTextView.text;
    self.clip.timeStart = self.startTime * 1000;
    self.clip.timeEnd = self.endTime * 1000;
    
    self.playerController.isLooping = NO;
    [self.delegate creationDone:self.clip];
    
}

- (IBAction)cancelAction:(id)sender
{
    [self stopMonitorPlaybackTimer];
    self.playerController.isLooping = NO;
    [self.delegate creationCanceled];
}

- (void)updateUI
{
    self.startTimeLabel.text = [Clip formatTimeWithSeconds:self.startTimeIntermediate];
    self.endTimeLabel.text = [Clip formatTimeWithSeconds:self.endTimeIntermediate];
    self.playerController.startTime = self.startTime;
    self.playerController.endTime = self.endTime;
}

- (void)setStartTimeIntermediate:(CGFloat)startTimeIntermediate
{
    _startTimeIntermediate = startTimeIntermediate;
    [self updateUI];
    [self.playerController seekToExactTime:startTimeIntermediate done:nil];
}

- (void)setEndTimeIntermediate:(CGFloat)endTimeIntermediate
{
    _endTimeIntermediate = endTimeIntermediate;
    [self updateUI];
    [self.playerController seekToExactTime:endTimeIntermediate done:nil];
}

- (void)setStartTime:(CGFloat)startTime
{
    _startTime = startTime;
    self.startTimeIntermediate = startTime;
    self.playerController.startTime = startTime;
}

- (void)setEndTime:(CGFloat)endTime
{
    _endTime = endTime;
    self.endTimeIntermediate = endTime;
    self.playerController.endTime = endTime;
}

- (void)updateRulerData:(RulerView *)ruler
{
    ruler.startPos = startSliderHomePos;
    ruler.startTime = self.startTime;
    ruler.endPos = endSliderHomePos;
    ruler.endTime = self.endTime;
    ruler.sliderOffset = self.startSlider.frame.size.width/2;
    [ruler setNeedsDisplay];
}

- (void)onStartSliderDrag:(UIPanGestureRecognizer *)panGestureRecognizer
{
    CGPoint point    = [panGestureRecognizer locationInView:self.view];
    
    if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        self.startPosition = CGPointMake(point.x - self.startSlider.frame.origin.x, point.y - self.startSlider.frame.origin.y);
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
        float xPos = (point.x - self.startPosition.x);
        if (xPos < 0) {
            xPos = 0;
        }
        if (xPos > (self.endSlider.frame.origin.x - self.startSlider.frame.size.width)){
            xPos = self.endSlider.frame.origin.x - self.startSlider.frame.size.width;
        }
        self.startSlider.frame = CGRectMake( xPos, self.startSlider.frame.origin.y, self.startSlider.frame.size.width, self.startSlider.frame.size.height);
        [self resizeWindow];
        
        //update the Labels - DELETE
        CGFloat originalTimeDiff = self.endTime - self.startTime;
        CGFloat newTimeDiff = ((endSliderHomePos - self.startSlider.frame.origin.x)/(endSliderHomePos - startSliderHomePos))*originalTimeDiff;
        
        self.startTimeIntermediate = self.endTime-newTimeDiff;
        
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
        //update starting time
        CGFloat originalTimeDiff = self.endTime - self.startTime;
        CGFloat newTimeDiff = ((endSliderHomePos - self.startSlider.frame.origin.x)/(endSliderHomePos - startSliderHomePos))*originalTimeDiff;
        self.startTime = self.endTime-newTimeDiff;
        
        CGFloat newScale = (((originalTimeDiff/newTimeDiff)*self.rulerContainer.frame.size.width)-self.rulerContainer.frame.size.width)/2;
        CGFloat halfWidth = self.rulerContainer.frame.size.width/2;
        self.translation = -newScale*((self.endSlider.frame.origin.x+(self.endSlider.frame.size.width/2))-halfWidth)/halfWidth;
        
        CGAffineTransform translate = CGAffineTransformMakeTranslation(self.translation,0);
        CGAffineTransform scale = CGAffineTransformMakeScale(originalTimeDiff/newTimeDiff, 1.0);
        CGAffineTransform transform =  CGAffineTransformConcat(scale, translate);
        RulerView *rulerView = self.rulerView;
        
        [UIView animateWithDuration:0.5 animations:^{
            self.startSlider.frame = CGRectMake( startSliderHomePos, self.startSlider.frame.origin.y, self.startSlider.frame.size.width, self.startSlider.frame.size.height);
            [self resizeWindow];
            rulerView.transform = transform;
        } completion:^(BOOL finished) {
            [rulerView removeFromSuperview];
            self.rulerView = [[RulerView alloc] initWithFrame:CGRectMake(0,0,self.rulerContainer.frame.size.width, self.rulerContainer.frame.size.height)];
            [self.rulerContainer addSubview:self.rulerView];
            [self updateRulerData:self.rulerView];
        }];
    }
}

- (void)onEndSliderDrag:(UIPanGestureRecognizer *)panGestureRecognizer
{
    CGPoint point    = [panGestureRecognizer locationInView:self.view];
    if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        self.playerController.isLooping = NO;
        self.endPosition = CGPointMake(point.x - self.endSlider.frame.origin.x, point.y - self.endSlider.frame.origin.y);
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
        float xPos = (point.x - self.endPosition.x);
        if (xPos > 320-(self.endSlider.frame.size.width)) {
            xPos = 320-(self.endSlider.frame.size.width);
        }
        if (xPos < (self.startSlider.frame.origin.x + self.startSlider.frame.size.width)) {
            xPos = (self.startSlider.frame.origin.x + self.startSlider.frame.size.width);
        }
        self.endSlider.frame = CGRectMake( xPos, self.endSlider.frame.origin.y, self.endSlider.frame.size.width, self.endSlider.frame.size.height);
        [self resizeWindow];
        
        //update ending time
        CGFloat originalTimeDiff = self.endTime - self.startTime;
        CGFloat newTimeDiff = ((self.endSlider.frame.origin.x - startSliderHomePos)/(endSliderHomePos - startSliderHomePos))*originalTimeDiff;
        
        self.endTimeIntermediate = self.startTime+newTimeDiff;
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
        self.playerController.isLooping = YES;
        //update ending time
        CGFloat originalTimeDiff = self.endTime - self.startTime;
        CGFloat newTimeDiff = ((self.endSlider.frame.origin.x - startSliderHomePos)/(endSliderHomePos - startSliderHomePos))*originalTimeDiff;
        self.endTime = self.startTime+newTimeDiff;
        
        CGFloat newScale = (((originalTimeDiff/newTimeDiff)*self.rulerContainer.frame.size.width)-self.rulerContainer.frame.size.width)/2;
        self.translation = newScale*(((self.rulerContainer.frame.size.width/2)-(startSliderHomePos+(self.startSlider.frame.size.width/2)))/(self.rulerContainer.frame.size.width/2));
        
        CGAffineTransform translate = CGAffineTransformMakeTranslation(self.translation,0);
        CGAffineTransform scale = CGAffineTransformMakeScale(originalTimeDiff/newTimeDiff, 1.0);
        CGAffineTransform transform =  CGAffineTransformConcat(scale, translate);
        RulerView *rulerView = self.rulerView;
        
        [UIView animateWithDuration:0.5 animations:^{
            self.endSlider.frame = CGRectMake( endSliderHomePos, self.endSlider.frame.origin.y, self.endSlider.frame.size.width, self.endSlider.frame.size.height);
            [self resizeWindow];
            rulerView.transform = transform;
        } completion:^(BOOL finished) {
            [rulerView removeFromSuperview];
            self.rulerView = [[RulerView alloc] initWithFrame:CGRectMake(0,0,self.rulerContainer.frame.size.width, self.rulerContainer.frame.size.height)];
            [self.rulerContainer addSubview:self.rulerView];
            [self updateRulerData:self.rulerView];
        }];
    }
}

- (void)resizeWindow
{
    CGFloat startPos = self.startSlider.frame.origin.x + self.startSlider.frame.size.width;
    CGFloat endPos = self.endSlider.frame.origin.x;
    self.sliderWindow.frame = CGRectMake(startPos, self.sliderWindow.frame.origin.y, endPos-startPos, self.sliderWindow.frame.size.height);
    
    CGFloat startCenterPos = self.startSlider.frame.origin.x + (self.startSlider.frame.size.width/2.0);
    CGFloat endCenterPos = self.endSlider.frame.origin.x + (self.endSlider.frame.size.width/2.0);
    CGFloat startLabelPos = startCenterPos - (self.startTimeLabel.frame.size.width/2);
    CGFloat endLabelPos = endCenterPos - (self.endTimeLabel.frame.size.width/2);
    
    self.startTimeLabel.frame = CGRectMake(startLabelPos, self.startTimeLabel.frame.origin.y, self.startTimeLabel.frame.size.width, self.startTimeLabel.frame.size.height);
    
    self.endTimeLabel.frame = CGRectMake(endLabelPos, self.endTimeLabel.frame.origin.y, self.endTimeLabel.frame.size.width, self.endTimeLabel.frame.size.height);
}

#pragma mark - Current Playback
- (void)startMonitorPlaybackTimer
{
    __weak typeof(self) weakSelf = self;
    self.timeObserverHandle = [self.playerController addTimeObserverWithBlock:^(float time) {
        [weakSelf monitorPlayback:time];
    }];
}

- (void)stopMonitorPlaybackTimer
{
    [self.playerController removeTimeObserver:self.timeObserverHandle];
}

- (void)monitorPlayback:(float)currentPlaybackTime
{
    CGFloat startPosition = self.startSlider.frame.origin.x + self.startSlider.frame.size.width;
    CGFloat endPosition = self.endSlider.frame.origin.x;

    // Get percent of loop played
    CGFloat percentPlayed = (currentPlaybackTime - self.startTime) / (self.endTime - self.startTime);
    // Convert percent played to position between handles
    self.currentPlaybackPosition = (endPosition - startPosition) * percentPlayed + startPosition;
}

- (void)setCurrentPlaybackPosition:(CGFloat)currentPlaybackPosition
{
    // Change position of current line view
    CGRect frame = self.playbackProgressView.frame;
    self.playbackProgressView.frame = CGRectMake(currentPlaybackPosition, frame.origin.y, frame.size.width, frame.size.height);
    _currentPlaybackPosition = currentPlaybackPosition;
}


@end
