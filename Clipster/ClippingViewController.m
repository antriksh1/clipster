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

@interface ClippingViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *startSlider;
@property (weak, nonatomic) IBOutlet UIImageView *endSlider;
@property (nonatomic, assign) CGPoint startPosition;
@property (nonatomic, assign) CGPoint   endPosition;
@property (weak, nonatomic) IBOutlet UIView *rulerContainer;
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
@property (nonatomic, strong) MPMoviePlayerController *player;
@property (weak, nonatomic) IBOutlet RPFloatingPlaceholderTextView *annotationTextView;
@end

@implementation ClippingViewController

static CGFloat startSliderHomePos = 50;
static CGFloat   endSliderHomePos = 240;

- (id)init
{
    self = [super init];
    if (self) {
        // Custom initialization
        self.title = @"Clipping";
    }
    return self;
}

- (id)initWithClip:(Clip*)clip moviePlayer:(MPMoviePlayerController*)player
{
    self = [self init];
    if (self) {
        _clip = clip;
        _player = player;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAction)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStylePlain target:self action:@selector(doneAction:)];
    
    self.annotationTextView.delegate = self;
    self.annotationTextView.placeholder = @"Enter description";

    if ([self respondsToSelector:@selector(edgesForExtendedLayout)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    // Add pan gestures to draggable sliders
    UIPanGestureRecognizer *startPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onStartSliderDrag:)];
    [self.startSlider addGestureRecognizer:startPanGestureRecognizer];
    
    UIPanGestureRecognizer *endPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onEndSliderDrag:)];
    [self.endSlider addGestureRecognizer:endPanGestureRecognizer];
    
    // Draw the ruler
    RulerView *ruler = [[RulerView alloc] initWithFrame:CGRectMake(0, 0, self.rulerContainer.frame.size.width, self.rulerContainer.frame.size.height)];
    [self.rulerContainer addSubview:ruler];
    self.startTime = self.clip.timeStart / 1000.0f;
    self.endTime = self.clip.timeEnd / 1000.0f;
    [self updateRulerData:ruler];

    // add the player to ourself
    [self.player pause];
    [self.player.view setFrame: self.videoPlayerContainer.frame];
    [self.videoPlayerContainer addSubview: self.player.view];
    [self.view bringSubviewToFront:self.videoPlayerContainer];
    self.player.fullscreen = NO;
}

#pragma mark - UITextViewDelegate
- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self.scrollView setContentOffset:self.rulerContainer.frame.origin animated:YES];
}

- (IBAction)tapAction:(id)sender {
    if (self.annotationTextView.isFirstResponder) {
        [self.annotationTextView resignFirstResponder];
    }
    [self.scrollView setContentOffset:self.videoPlayerContainer.frame.origin animated:YES];
}

- (void)doneAction:(id)sender {
    self.clip.text = self.annotationTextView.text;
    self.clip.timeStart = self.startTime * 1000;
    self.clip.timeEnd = self.endTime * 1000;
    [self.delegate creationDone:self.clip];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)cancelAction
{
    [self.delegate creationCanceled];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)updateUI:(BOOL)isEndChanged
{
    if (isEndChanged) {
        self.player.currentPlaybackTime = self.endTimeIntermediate;
    } else {
        self.player.currentPlaybackTime = self.startTimeIntermediate;
    }
    
    self.startTimeLabel.text = [Clip formatTimeWithSeconds:self.startTimeIntermediate];
    self.endTimeLabel.text = [Clip formatTimeWithSeconds:self.endTimeIntermediate];
}

- (void)setStartTimeIntermediate:(CGFloat)startTimeIntermediate
{
    _startTimeIntermediate = startTimeIntermediate;
    [self updateUI:NO];
}

- (void)setEndTimeIntermediate:(CGFloat)endTimeIntermediate
{
    _endTimeIntermediate = endTimeIntermediate;
    [self updateUI:YES];
}

- (void)setStartTime:(CGFloat)startTime
{
    _startTime = startTime;
    self.startTimeIntermediate = startTime;
}

- (void)setEndTime:(CGFloat)endTime
{
    _endTime = endTime;
    self.endTimeIntermediate = endTime;
}

- (void)updateRulerData:(RulerView *)ruler{
    ruler.startPos = startSliderHomePos;
    ruler.startTime = self.startTime;
    ruler.endPos = endSliderHomePos;
    ruler.endTime = self.endTime;
    ruler.sliderOffset = self.startSlider.frame.size.width/2;
    NSLog(@"START %f END %f", self.startTime, self.endTime);
    
    [ruler setNeedsDisplay];
}

- (void)onStartSliderDrag:(UIPanGestureRecognizer *)panGestureRecognizer{
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
        RulerView *rulerView = self.rulerContainer.subviews[0];
        
        [UIView animateWithDuration:0.5 animations:^{
            self.startSlider.frame = CGRectMake( startSliderHomePos, self.startSlider.frame.origin.y, self.startSlider.frame.size.width, self.startSlider.frame.size.height);
            rulerView.transform = transform;
        } completion:^(BOOL finished) {
            NSLog(@"returned start slider to home position");
            [rulerView removeFromSuperview];
            RulerView *newRulerView = [[RulerView alloc] initWithFrame:CGRectMake(0,0,self.rulerContainer.frame.size.width, self.rulerContainer.frame.size.height)];
            [self.rulerContainer addSubview:newRulerView];
            [self updateRulerData:newRulerView];
        }];
    }
}

- (void)onEndSliderDrag:(UIPanGestureRecognizer *)panGestureRecognizer{
    CGPoint point    = [panGestureRecognizer locationInView:self.view];
    if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        self.endPosition = CGPointMake(point.x - self.endSlider.frame.origin.x, point.y - self.endSlider.frame.origin.y);
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
        float xPos = (point.x - self.endPosition.x);
        if (xPos > 320-(self.endSlider.frame.size.width)) {
            xPos = 320-(self.endSlider.frame.size.width);
        }
        if (xPos < (self.startSlider.frame.origin.x + self.startSlider.frame.size.width)){
            xPos = (self.startSlider.frame.origin.x + self.startSlider.frame.size.width);
        }
        self.endSlider.frame = CGRectMake( xPos, self.endSlider.frame.origin.y, self.endSlider.frame.size.width, self.endSlider.frame.size.height);
        
        //update ending time
        CGFloat originalTimeDiff = self.endTime - self.startTime;
        CGFloat newTimeDiff = ((self.endSlider.frame.origin.x - startSliderHomePos)/(endSliderHomePos - startSliderHomePos))*originalTimeDiff;
        
        self.endTimeIntermediate = self.startTime+newTimeDiff;
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
        //update ending time
        CGFloat originalTimeDiff = self.endTime - self.startTime;
        CGFloat newTimeDiff = ((self.endSlider.frame.origin.x - startSliderHomePos)/(endSliderHomePos - startSliderHomePos))*originalTimeDiff;
        self.endTime = self.startTime+newTimeDiff;
        NSLog(@"%f", self.endTime);
        
        CGFloat newScale = (((originalTimeDiff/newTimeDiff)*self.rulerContainer.frame.size.width)-self.rulerContainer.frame.size.width)/2;
        self.translation = newScale*(((self.rulerContainer.frame.size.width/2)-(startSliderHomePos+(self.startSlider.frame.size.width/2)))/(self.rulerContainer.frame.size.width/2));
        
        CGAffineTransform translate = CGAffineTransformMakeTranslation(self.translation,0);
        CGAffineTransform scale = CGAffineTransformMakeScale(originalTimeDiff/newTimeDiff, 1.0);
        CGAffineTransform transform =  CGAffineTransformConcat(scale, translate);
        RulerView *rulerView = self.rulerContainer.subviews[0];
        
        [UIView animateWithDuration:0.5 animations:^{
            self.endSlider.frame = CGRectMake( endSliderHomePos, self.endSlider.frame.origin.y, self.endSlider.frame.size.width, self.endSlider.frame.size.height);
            rulerView.transform = transform;
        } completion:^(BOOL finished) {
            NSLog(@"returned end slider to home position");
            [rulerView removeFromSuperview];
            RulerView *newRulerView = [[RulerView alloc] initWithFrame:CGRectMake(0,0,self.rulerContainer.frame.size.width, self.rulerContainer.frame.size.height)];
            [self.rulerContainer addSubview:newRulerView];
            [self updateRulerData:newRulerView];
        }];
        
        
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
