//
// UIScrollView+SVPullToRefresh.m
//
// Created by Sam Vermette on 23.04.12.
// Copyright (c) 2012 samvermette.com. All rights reserved.
//
// https://github.com/samvermette/SVPullToRefresh
//

#import <QuartzCore/QuartzCore.h>
#import "UIScrollView+SVPullToRefresh.h"

//fequal() and fequalzro() from http://stackoverflow.com/a/1614761/184130
#define fequal(a,b) (fabs((a) - (b)) < FLT_EPSILON)
#define fequalzero(a) (fabs(a) < FLT_EPSILON)

static CGFloat const SVPullToRefreshViewHeight = 60;
static CGFloat const SVPullToRefreshViewImageHeight = 40;

@interface SVPullToRefreshArrow : UIView

@property (nonatomic, strong) UIColor *arrowColor;

@end

@interface SVPullToRefreshView ()

@property (nonatomic, copy) void (^pullToRefreshActionHandler)(void);

@property (nonatomic, readwrite) SVPullToRefreshState state;
@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, readwrite) CGFloat originalTopInset;
@property (nonatomic, readwrite) CGFloat originalBottomInset;
@property (nonatomic, assign) BOOL wasTriggeredByUser;
@property (nonatomic, assign) BOOL showsPullToRefresh;
@property (nonatomic, assign) BOOL isObserving;

- (void)resetScrollViewContentInset;
- (void)setScrollViewContentInsetForLoading;
- (void)setScrollViewContentInset:(UIEdgeInsets)insets;

@end

#pragma mark - UIScrollView (SVPullToRefresh)
#import <objc/runtime.h>

static char UIScrollViewPullToRefreshView;

@implementation UIScrollView (SVPullToRefresh)

@dynamic pullToRefreshView, showsPullToRefresh;

- (void)addPullToRefreshWithActionHandler:(void (^)(void))actionHandler
{
  if(!self.pullToRefreshView) {
    CGFloat yOrigin = -SVPullToRefreshViewHeight;
    
    SVPullToRefreshView *view = [[SVPullToRefreshView alloc] initWithFrame:CGRectMake(0, yOrigin, self.bounds.size.width, SVPullToRefreshViewHeight)];
    view.pullToRefreshActionHandler = actionHandler;
    view.scrollView = self;
    [self addSubview:view];
    
    view.originalTopInset = self.contentInset.top;
    view.originalBottomInset = self.contentInset.bottom;
    self.pullToRefreshView = view;
    self.showsPullToRefresh = YES;
  }
}

- (void)triggerPullToRefresh
{
  self.pullToRefreshView.state = SVPullToRefreshStateTriggered;
  [self.pullToRefreshView startAnimating];
}

- (void)setPullToRefreshView:(SVPullToRefreshView *)pullToRefreshView
{
  [self willChangeValueForKey:@"SVPullToRefreshView"];
  objc_setAssociatedObject(self, &UIScrollViewPullToRefreshView,
                           pullToRefreshView,
                           OBJC_ASSOCIATION_ASSIGN);
  [self didChangeValueForKey:@"SVPullToRefreshView"];
}

- (SVPullToRefreshView *)pullToRefreshView
{
  return objc_getAssociatedObject(self, &UIScrollViewPullToRefreshView);
}

- (void)setShowsPullToRefresh:(BOOL)showsPullToRefresh
{
  self.pullToRefreshView.hidden = !showsPullToRefresh;
  
  if(!showsPullToRefresh) {
    if (self.pullToRefreshView.isObserving) {
      [self removeObserver:self.pullToRefreshView forKeyPath:@"contentOffset"];
      [self removeObserver:self.pullToRefreshView forKeyPath:@"contentSize"];
      [self removeObserver:self.pullToRefreshView forKeyPath:@"frame"];
      [self.pullToRefreshView resetScrollViewContentInset];
      self.pullToRefreshView.isObserving = NO;
    }
  }
  else {
    if (!self.pullToRefreshView.isObserving) {
      [self addObserver:self.pullToRefreshView forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
      [self addObserver:self.pullToRefreshView forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];
      [self addObserver:self.pullToRefreshView forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
      self.pullToRefreshView.isObserving = YES;
      
      CGFloat yOrigin = -SVPullToRefreshViewHeight;
      
      self.pullToRefreshView.frame = CGRectMake(0, yOrigin, self.bounds.size.width, SVPullToRefreshViewHeight);
    }
  }
}

- (BOOL)showsPullToRefresh
{
  return !self.pullToRefreshView.hidden;
}

@end

#pragma mark - SVPullToRefresh
@implementation SVPullToRefreshView

@synthesize pullToRefreshActionHandler;

@synthesize state = _state;
@synthesize scrollView = _scrollView;
@synthesize showsPullToRefresh = _showsPullToRefresh;

- (id)initWithFrame:(CGRect)frame
{
  if(self = [super initWithFrame:frame])
  {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.state = SVPullToRefreshStateStopped;
    self.wasTriggeredByUser = YES;
    [self initLoadingViews];
  }
  
  return self;
}

- (void)initLoadingViews
{
  UIImage* image = [UIImage imageNamed:@"SVCutomLoadingImage"];
  self.imageView = [[UIImageView alloc] initWithImage:image];
  [self addSubview:self.imageView];
  [self updateImageViewWithPercent:0];
}

- (void)startRotateAnimation
{
  [CATransaction begin];
  [CATransaction setValue:(id)kCFBooleanFalse forKey:kCATransactionDisableActions];
  [CATransaction setValue:[NSNumber numberWithFloat:1.618f]
                   forKey:kCATransactionAnimationDuration];
  CABasicAnimation* rotateAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
  rotateAnimation.toValue = [NSNumber numberWithFloat: M_PI * 2.0 ];
  rotateAnimation.repeatCount = HUGE_VAL;
  [self.imageView.layer addAnimation:rotateAnimation forKey:@"rotationAnimation"];
  [CATransaction commit];
}

- (void)stopRotateAnimation
{
  [self.imageView.layer removeAnimationForKey:@"rotationAnimation"];
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
  if (self.superview && newSuperview == nil) {
    //use self.superview, not self.scrollView. Why self.scrollView == nil here?
    UIScrollView *scrollView = (UIScrollView *)self.superview;
    if (scrollView.showsPullToRefresh) {
      if (self.isObserving) {
        //If enter this branch, it is the moment just before "SVPullToRefreshView's dealloc", so remove observer here
        [scrollView removeObserver:self forKeyPath:@"contentOffset"];
        [scrollView removeObserver:self forKeyPath:@"contentSize"];
        [scrollView removeObserver:self forKeyPath:@"frame"];
        self.isObserving = NO;
      }
    }
  }
}

#pragma mark - Scroll View

- (void)resetScrollViewContentInset
{
  UIEdgeInsets currentInsets = self.scrollView.contentInset;
  currentInsets.top = self.originalTopInset;
  
  [self setScrollViewContentInset:currentInsets];
}

- (void)setScrollViewContentInsetForLoading
{
  CGFloat offset = MAX(self.scrollView.contentOffset.y * -1, 0);
  UIEdgeInsets currentInsets = self.scrollView.contentInset;
  currentInsets.top = MIN(offset, self.originalTopInset + self.bounds.size.height);
  [self setScrollViewContentInset:currentInsets];
}

- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset
{
  [UIView animateWithDuration:0.3
                        delay:0
                      options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     self.scrollView.contentInset = contentInset;
                   }
                   completion:NULL];
}

#pragma mark - Observing

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
  if([keyPath isEqualToString:@"contentOffset"])
    [self scrollViewDidScroll:[[change valueForKey:NSKeyValueChangeNewKey] CGPointValue]];
  else if([keyPath isEqualToString:@"contentSize"]) {
    [self layoutSubviews];
    
    CGFloat yOrigin = -SVPullToRefreshViewHeight;
    self.frame = CGRectMake(0, yOrigin, self.bounds.size.width, SVPullToRefreshViewHeight);
  }
  else if([keyPath isEqualToString:@"frame"]) {
    [self layoutSubviews];
  }
}

- (void)scrollViewDidScroll:(CGPoint)contentOffset
{
  if(self.state != SVPullToRefreshStateLoading)
  {
    CGFloat scrollOffsetThreshold = self.frame.origin.y - self.originalTopInset;
    
    if(self.state == SVPullToRefreshStateTriggered)
    {
      if (!self.scrollView.isDragging)
      {
        self.state = SVPullToRefreshStateLoading;
      }
      else if(self.scrollView.isDragging && contentOffset.y >= scrollOffsetThreshold && contentOffset.y < 0)
      {
        self.state = SVPullToRefreshStateStopped;
        CGFloat percent = contentOffset.y/scrollOffsetThreshold;
        [self updateImageViewWithPercent:percent];
      }
      
    }
    else if(self.state == SVPullToRefreshStateStopped)
    {
      if (contentOffset.y < scrollOffsetThreshold && self.scrollView.isDragging)
      {
        self.state = SVPullToRefreshStateTriggered;
        [self updateImageViewWithPercent:1];
      }
      else if(contentOffset.y >= scrollOffsetThreshold && contentOffset.y < 0)
      {
        CGFloat percent = contentOffset.y/scrollOffsetThreshold;
        [self updateImageViewWithPercent:percent];
      }
      
    }
    else if(self.state != SVPullToRefreshStateStopped )
    {
      if (contentOffset.y >= scrollOffsetThreshold) {
        self.state = SVPullToRefreshStateStopped;
      }
    }
  }
  else
  {
    CGFloat offset = MAX(self.scrollView.contentOffset.y * -1, 0.0f);
    offset = MIN(offset, self.originalTopInset + self.bounds.size.height);
    UIEdgeInsets contentInset = self.scrollView.contentInset;
    self.scrollView.contentInset = UIEdgeInsetsMake(offset, contentInset.left, contentInset.bottom, contentInset.right);
  }
}

#pragma mark -

- (void)startAnimating
{
  if(fequalzero(self.scrollView.contentOffset.y)) {
    [self.scrollView setContentOffset:CGPointMake(self.scrollView.contentOffset.x, -self.frame.size.height) animated:YES];
    self.wasTriggeredByUser = NO;
  }
  else
    self.wasTriggeredByUser = YES;
  
  self.state = SVPullToRefreshStateLoading;
}

- (void)stopAnimating
{
  self.state = SVPullToRefreshStateStopped;
  
  if(!self.wasTriggeredByUser)
    [self.scrollView setContentOffset:CGPointMake(self.scrollView.contentOffset.x, -self.originalTopInset) animated:YES];
}

- (void)setState:(SVPullToRefreshState)newState
{
  if(_state == newState)
    return;
  
  SVPullToRefreshState previousState = _state;
  _state = newState;
  
  [self setNeedsLayout];
  [self layoutIfNeeded];
  
  switch (newState) {
    case SVPullToRefreshStateAll:
    case SVPullToRefreshStateStopped:
      
      [self stopRotateAnimation];
      [self resetScrollViewContentInset];
      
      break;
      
    case SVPullToRefreshStateTriggered:
      break;
      
    case SVPullToRefreshStateLoading:
      
      [self updateImageViewWithPercent:1];
      [self startRotateAnimation];
      [self setScrollViewContentInsetForLoading];
      
      if(previousState == SVPullToRefreshStateTriggered && pullToRefreshActionHandler) {
        pullToRefreshActionHandler();
      }
      
      break;
  }
}

// percent is zoom
- (void)updateImageViewWithPercent:(CGFloat)percent
{
  self.imageView.center = CGPointMake(self.frame.size.width/2,
                                      self.frame.size.height/2);
  
  CAShapeLayer* maskLayer = [CAShapeLayer layer];
  UIBezierPath* path = [UIBezierPath bezierPath];
  CGPoint centerPoint = CGPointMake(SVPullToRefreshViewImageHeight/3.23,SVPullToRefreshViewImageHeight/3.23);
  [path moveToPoint:centerPoint];
  [path addArcWithCenter:centerPoint
                  radius:SVPullToRefreshViewImageHeight/2
              startAngle:-M_PI_2
                endAngle:-M_PI_2+M_PI*percent*2
               clockwise:YES];
  [path closePath];
  maskLayer.path = path.CGPath;
  maskLayer.frame = self.imageView.bounds;
  maskLayer.contentsScale = [UIScreen mainScreen].scale;
  self.imageView.layer.mask = maskLayer;
}

@end
