#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

static void *const BMBatteryViewKey=(void *)&BMBatteryViewKey;
static void *const BMOverlayLabelKey=(void *)&BMOverlayLabelKey;
static void *const BMLabelContainerFrameKey=(void *)&BMLabelContainerFrameKey;
static void *const BMStableMaxFontSizeKey=(void *)&BMStableMaxFontSizeKey;
static void *const BMManagedBatteryViewKey=(void *)&BMManagedBatteryViewKey;
static void *const BMManagedBatteryViewActiveKey=(void *)&BMManagedBatteryViewActiveKey;
static NSHashTable<UIViewController *> *BMTrackedControllers=nil;

@interface _UIBatteryView:UIView
@property(nonatomic,assign) double chargePercent;
- (instancetype)initWithSizeCategory:(NSInteger)sizeCategory;
- (void)setChargePercent:(double)percent;
- (void)setShowsPercentage:(BOOL)showsPercentage;
- (void)setSaverModeActive:(BOOL)active;
- (void)setInternalSizeCategory:(NSInteger)sizeCategory;
- (void)setFillColor:(UIColor *)color;
- (void)setBodyColor:(UIColor *)color;
- (void)setPinColor:(UIColor *)color;
- (void)setInactiveColor:(UIColor *)color;
- (void)setBoltColor:(UIColor *)color;
- (UIColor *)_batteryFillColor;
- (UIColor *)_batteryUnfilledColor;
- (UIColor *)_batteryTextColor;
- (UIColor *)bodyColor;
- (UIColor *)pinColor;
- (void)setBodyColorAlpha:(double)alpha;
- (void)setPinColorAlpha:(double)alpha;
@end

static _UIBatteryView *BMBatteryViewForController(UIViewController *c){
	return objc_getAssociatedObject(c,BMBatteryViewKey);
}

static UILabel *BMOverlayLabelForBatteryView(_UIBatteryView *v){
	return objc_getAssociatedObject(v,BMOverlayLabelKey);
}

static void BMSetBatteryViewForController(UIViewController *c,_UIBatteryView *v){
	objc_setAssociatedObject(c,BMBatteryViewKey,v,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UILabel *BMEnsureOverlayLabel(_UIBatteryView *v){
	UILabel *l=BMOverlayLabelForBatteryView(v);
	if(l)return l;
	l=[[UILabel alloc]initWithFrame:CGRectZero];
	l.userInteractionEnabled=NO;
	l.backgroundColor=UIColor.clearColor;
	l.textAlignment=NSTextAlignmentCenter;
	l.numberOfLines=1;
	l.adjustsFontSizeToFitWidth=NO;
	[v addSubview:l];
	objc_setAssociatedObject(v,BMOverlayLabelKey,l,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return l;
}

static BOOL BMIsManagedBatteryView(_UIBatteryView *v){
	return [objc_getAssociatedObject(v,BMManagedBatteryViewKey) boolValue];
}

static void BMSetManagedBatteryView(_UIBatteryView *v,BOOL managed){
	objc_setAssociatedObject(v,BMManagedBatteryViewKey,@(managed),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL BMManagedBatteryViewIsActive(_UIBatteryView *v){
	return [objc_getAssociatedObject(v,BMManagedBatteryViewActiveKey) boolValue];
}

static void BMSetManagedBatteryViewActive(_UIBatteryView *v,BOOL active){
	objc_setAssociatedObject(v,BMManagedBatteryViewActiveKey,@(active),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL BMManagedBatteryViewIsInLowPowerMode(void){
	return [NSProcessInfo processInfo].lowPowerModeEnabled;
}

static BOOL BMManagedBatteryViewIsLowLevel(void){
	float level=[UIDevice currentDevice].batteryLevel;
	return level>=0.0f&&level<=0.20f;
}

static UIColor *BMManagedBatteryViewBaseColor(_UIBatteryView *v){
	return BMManagedBatteryViewIsActive(v)?[UIColor colorWithWhite:0.05 alpha:1.0]:[UIColor colorWithWhite:0.92 alpha:1.0];
}

static UIColor *BMManagedBatteryViewFillColor(_UIBatteryView *v){
	if(BMManagedBatteryViewIsInLowPowerMode())
		return [UIColor colorWithRed:0.96 green:0.82 blue:0.20 alpha:1.0];
	if(BMManagedBatteryViewIsLowLevel())
		return [UIColor colorWithRed:0.88 green:0.23 blue:0.19 alpha:1.0];
	return BMManagedBatteryViewBaseColor(v);
}

static UIColor *BMManagedBatteryViewTextColor(_UIBatteryView *v){
	if(BMManagedBatteryViewIsInLowPowerMode())return UIColor.blackColor;
	if(BMManagedBatteryViewIsLowLevel())return UIColor.whiteColor;
	if(BMManagedBatteryViewIsActive(v))return UIColor.whiteColor;
	return UIColor.blackColor;
}

static UIColor *BMManagedBatteryViewBodyColor(_UIBatteryView *v){
	return BMManagedBatteryViewBaseColor(v);
}

static UIColor *BMManagedBatteryViewInactiveColor(_UIBatteryView *v){
	return [BMManagedBatteryViewBaseColor(v) colorWithAlphaComponent:0.34];
}

static NSString *BMManagedBatteryViewDisplayedText(_UIBatteryView *v,UILabel *l){
	float level=[UIDevice currentDevice].batteryLevel;
	NSInteger percent=level<0.0f?0:(NSInteger)lroundf(level*100.0f);
	return [NSString stringWithFormat:@"%ld",(long)percent];
}

static UIFont *BMManagedBatteryViewFontToFitWidth(CGFloat targetWidth,CGFloat maxFontSize,NSString *referenceText){
	if(targetWidth<=1.0)targetWidth=18.0;
	CGFloat minFontSize=MAX(8.0,maxFontSize*0.6);
	UIFont *bestFont=[UIFont boldSystemFontOfSize:minFontSize];
	for(CGFloat fontSize=maxFontSize;fontSize>=minFontSize;fontSize-=0.5){
		UIFont *font=[UIFont boldSystemFontOfSize:fontSize];
		CGRect textRect=[referenceText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX,40.0)
			options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
			attributes:@{NSFontAttributeName:font} context:nil];
		bestFont=font;
		if(ceil(CGRectGetWidth(textRect))<=targetWidth)break;
	}
	return bestFont;
}

static CGFloat BMOverlayExtraWidth(void){
	return 11.0;
}

static CGFloat BMStableMaxFontSize(UILabel *l){
	NSNumber *cached=objc_getAssociatedObject(l,BMStableMaxFontSizeKey);
	if(cached)return cached.doubleValue;
	CGFloat maxFontSize=l.font.pointSize+7.0;
	if(maxFontSize<=0.0)maxFontSize=14.0;
	objc_setAssociatedObject(l,BMStableMaxFontSizeKey,@(maxFontSize),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return maxFontSize;
}

static void BMConfigureOverlayLabel(UILabel *l,UIColor *color){
	l.textColor=color;
	l.highlightedTextColor=color;
	l.tintColor=color;
	l.shadowColor=UIColor.clearColor;
	l.layer.shadowOpacity=0.0;
	l.layer.compositingFilter=nil;
}

static void BMEnumerateSubviews(UIView *view,void (^block)(UIView *subview)){
	if(!view||!block)return;
	block(view);
	for(UIView *subview in view.subviews)BMEnumerateSubviews(subview,block);
}

static void BMSetStockLowPowerArtworkHidden(UIViewController *c,BOOL hidden){
	_UIBatteryView *batteryView=BMBatteryViewForController(c);
	BMEnumerateSubviews(c.view,^(UIView *subview){
		if(subview==batteryView||(batteryView&&[subview isDescendantOfView:batteryView]))return;
		NSString *className=NSStringFromClass(subview.class);
		if([subview isKindOfClass:[UIImageView class]]||[className containsString:@"CCUICAPackageView"]){
			subview.hidden=hidden;
			subview.alpha=hidden?0.0:1.0;
		}
	});
}

static void BMHideStockLowPowerArtwork(UIViewController *c){
	BMSetStockLowPowerArtworkHidden(c,YES);
}

static _UIBatteryView *BMEnsureBatteryView(UIViewController *c){
	_UIBatteryView *v=BMBatteryViewForController(c);
	if(v)return v;
	Class cls=objc_getClass("_UIBatteryView");
	if(!cls||![cls instancesRespondToSelector:@selector(initWithSizeCategory:)])return nil;
	v=[(_UIBatteryView *)[cls alloc]initWithSizeCategory:0];
	v.userInteractionEnabled=NO;
	[c.view addSubview:v];
	BMSetBatteryViewForController(c,v);
	BMSetManagedBatteryView(v,YES);
	return v;
}

static void BMLayoutBatteryView(UIViewController *c){
	_UIBatteryView *v=BMBatteryViewForController(c);
	if(!v||!v.superview)return;
	CGRect bounds=c.view.bounds;
	CGFloat viewHeight=CGRectGetHeight(bounds);
	CGFloat width=MIN(CGRectGetWidth(bounds)-8.0,31.0);
	CGFloat height=16.0;
	CGFloat x=floor((CGRectGetWidth(bounds)-width)*0.5);
	BOOL expanded=viewHeight>120.0;
	CGFloat yRatio=expanded?0.25:0.50;
	CGFloat y=floor(viewHeight*yRatio-height*0.5);
	v.frame=CGRectMake(x,y,width,height);
	v.transform=CGAffineTransformMakeScale(1.30,1.30);
	[c.view bringSubviewToFront:v];
}

static BOOL BMShouldRoundBatteryLayer(CALayer *layer){
	if(!layer)return NO;
	CGRect b=layer.bounds;
	CGFloat w=CGRectGetWidth(b),h=CGRectGetHeight(b);
	return w>=5.0&&w<=40.0&&h>=5.0&&h<=20.0;
}

static void BMApplyCornerRadiusToLayerTree(CALayer *layer,CGFloat radius){
	if(!layer)return;
	if(BMShouldRoundBatteryLayer(layer)){
		layer.cornerRadius=MIN(radius,CGRectGetHeight(layer.bounds)*0.5);
		layer.masksToBounds=radius>0.0;
	}
	for(CALayer *sublayer in layer.sublayers)
		BMApplyCornerRadiusToLayerTree(sublayer,radius);
}

static void BMSetManagedBatteryVisibility(_UIBatteryView *v,BOOL visible){
	if(!v)return;
	v.hidden=!visible;
	v.alpha=visible?1.0:0.0;
	UILabel *l=BMOverlayLabelForBatteryView(v);
	if(l){
		l.hidden=!visible||l.attributedText.length==0;
		l.alpha=visible?1.0:0.0;
	}
}

static void BMApplyBatteryStyling(_UIBatteryView *v){
	if(!v)return;
	UIColor *fillColor=BMManagedBatteryViewFillColor(v);
	UIColor *bodyColor=BMManagedBatteryViewBodyColor(v);
	UIColor *inactiveColor=BMManagedBatteryViewInactiveColor(v);
	UIColor *pinColor=bodyColor;

	if([v respondsToSelector:@selector(setInternalSizeCategory:)])
		[v setInternalSizeCategory:1];
	if([v respondsToSelector:@selector(setFillColor:)])
		[v setFillColor:fillColor];
	if([v respondsToSelector:@selector(setBodyColor:)])
		[v setBodyColor:bodyColor];
	if([v respondsToSelector:@selector(setPinColor:)])
		[v setPinColor:pinColor];
	if([v respondsToSelector:@selector(setInactiveColor:)])
		[v setInactiveColor:inactiveColor];
	if([v respondsToSelector:@selector(setBoltColor:)])
		[v setBoltColor:fillColor];
	if([v respondsToSelector:@selector(setBodyColorAlpha:)])
		[v setBodyColorAlpha:1.0];
	if([v respondsToSelector:@selector(setPinColorAlpha:)])
		[v setPinColorAlpha:1.0];

	for(CALayer *sublayer in v.layer.sublayers)
		BMApplyCornerRadiusToLayerTree(sublayer,4.0);

	BMEnumerateSubviews(v,^(UIView *subview){
		if(![subview isKindOfClass:[UILabel class]])return;

		UILabel *label=(UILabel *)subview;
		UILabel *overlayLabel=BMEnsureOverlayLabel(v);
		if(label==overlayLabel)return;

		if(!objc_getAssociatedObject(label,BMLabelContainerFrameKey))
			objc_setAssociatedObject(label,BMLabelContainerFrameKey,[NSValue valueWithCGRect:label.frame],OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		CGRect containerFrame=[objc_getAssociatedObject(label,BMLabelContainerFrameKey) CGRectValue];
		CGFloat overlayWidth=CGRectGetWidth(containerFrame)+BMOverlayExtraWidth();
		CGFloat overlayOriginX=CGRectGetMidX(containerFrame)-(overlayWidth*0.5);
		CGFloat maxFontSize=BMStableMaxFontSize(label);
		UIColor *textColor=BMManagedBatteryViewTextColor(v);
		NSString *displayText=BMManagedBatteryViewDisplayedText(v,label);

		label.hidden=YES;
		label.alpha=0.0;

		if(displayText.length>0){
			UIFont *normalFont=BMManagedBatteryViewFontToFitWidth(overlayWidth,maxFontSize,@"100");
			UIFont *displayFont=normalFont;

			if([displayText isEqualToString:@"100"])
				displayFont=[UIFont boldSystemFontOfSize:normalFont.pointSize*0.90];

			BMConfigureOverlayLabel(overlayLabel,textColor);
			overlayLabel.font=displayFont;
			overlayLabel.frame=CGRectMake(overlayOriginX,CGRectGetMinY(containerFrame)-0.2,overlayWidth,CGRectGetHeight(containerFrame));
			overlayLabel.attributedText=[[NSAttributedString alloc]initWithString:displayText
				attributes:@{NSForegroundColorAttributeName:textColor,NSFontAttributeName:displayFont}];
			overlayLabel.hidden=NO;
			overlayLabel.alpha=1.0;
			overlayLabel.transform=CGAffineTransformIdentity;
			[v bringSubviewToFront:overlayLabel];
		}else{
			overlayLabel.frame=containerFrame;
			overlayLabel.attributedText=nil;
			overlayLabel.hidden=YES;
			overlayLabel.alpha=0.0;
			overlayLabel.transform=CGAffineTransformIdentity;
		}
	});
}

static BOOL BMControllerModuleIsActive(UIViewController *c){
	BOOL lowPowerModeEnabled=[NSProcessInfo processInfo].lowPowerModeEnabled;
	id module=nil;
	@try{module=[c valueForKey:@"module"];}
	@catch(__unused NSException *e){module=nil;}

	if([module respondsToSelector:@selector(isSelected)]){
		BOOL selected=((BOOL(*)(id,SEL))objc_msgSend)(module,@selector(isSelected));
		return selected||lowPowerModeEnabled;
	}
	return lowPowerModeEnabled;
}

static void BMRefreshLowPowerLabel(UIViewController *c){
	BMHideStockLowPowerArtwork(c);
	_UIBatteryView *v=BMEnsureBatteryView(c);
	UIDevice *device=[UIDevice currentDevice];
	device.batteryMonitoringEnabled=YES;
	float batteryLevel=device.batteryLevel;
	BOOL active=BMControllerModuleIsActive(c);

	if(v){
		BMSetManagedBatteryVisibility(v,YES);
		[v setChargePercent:(batteryLevel<0.0f?0.0:batteryLevel)];

		if([v respondsToSelector:@selector(setSaverModeActive:)])
			[v setSaverModeActive:active];
		if([v respondsToSelector:@selector(setShowsPercentage:)])
			[v setShowsPercentage:YES];

		BMSetManagedBatteryViewActive(v,active);
		BMApplyBatteryStyling(v);
	}
	BMLayoutBatteryView(c);
}

static BOOL BMIsLowPowerModuleController(UIViewController *c){
	NSString *className=NSStringFromClass(c.class);
	return [className isEqualToString:@"CCUILowPowerModuleViewController"]||
		[className containsString:@"LowPowerModuleViewController"];
}

static void BMTrackController(UIViewController *c){
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken,^{
		BMTrackedControllers=[NSHashTable weakObjectsHashTable];
	});
	[BMTrackedControllers addObject:c];
}

static void BMRefreshTrackedControllers(NSString *reason){
	if(![NSThread isMainThread]){
		dispatch_async(dispatch_get_main_queue(),^{
			BMRefreshTrackedControllers(reason);
		});
		return;
	}

	for(UIViewController *c in BMTrackedControllers){
		if(!c||!c.isViewLoaded)continue;
		BMRefreshLowPowerLabel(c);
	}
}

static void BMHandleControllerEvent(UIViewController *c,NSString *eventName){
	if(!BMIsLowPowerModuleController(c)||!c.isViewLoaded)return;
	BMTrackController(c);
	BMRefreshLowPowerLabel(c);
}

@interface BMBatteryMirrorObserver:NSObject
@end

@implementation BMBatteryMirrorObserver

- (instancetype)init{
	self=[super init];
	if(!self)return nil;

	NSNotificationCenter *center=[NSNotificationCenter defaultCenter];

	[center addObserver:self
		selector:@selector(handlePowerStateChange:)
		name:NSProcessInfoPowerStateDidChangeNotification
		object:nil];

	[center addObserver:self
		selector:@selector(handleBatteryChange:)
		name:UIDeviceBatteryLevelDidChangeNotification
		object:nil];

	return self;
}

- (void)handlePowerStateChange:(NSNotification *)notification{
	BMRefreshTrackedControllers(notification.name);
}

- (void)handleBatteryChange:(NSNotification *)notification{
	BMRefreshTrackedControllers(notification.name);
}

@end

%hook _UIBatteryView

- (void)layoutSubviews{
	%orig;
	if(BMIsManagedBatteryView(self))
		BMApplyBatteryStyling(self);
}

- (UIColor *)_batteryFillColor{
	if(BMIsManagedBatteryView(self))
		return BMManagedBatteryViewFillColor(self);
	return %orig;
}

- (UIColor *)_batteryTextColor{
	if(BMIsManagedBatteryView(self))
		return BMManagedBatteryViewTextColor(self);
	return %orig;
}

- (UIColor *)_batteryUnfilledColor{
	if(BMIsManagedBatteryView(self))
		return BMManagedBatteryViewInactiveColor(self);
	return %orig;
}

- (UIColor *)bodyColor{
	if(BMIsManagedBatteryView(self))
		return BMManagedBatteryViewBodyColor(self);
	return %orig;
}

- (UIColor *)pinColor{
	if(BMIsManagedBatteryView(self))
		return BMManagedBatteryViewBodyColor(self);
	return %orig;
}

%end

%hook UIViewController

- (void)viewDidLoad{
	%orig;
	BMHandleControllerEvent((UIViewController *)self,@"viewDidLoad");
}

- (void)viewWillAppear:(BOOL)animated{
	%orig(animated);
	BMHandleControllerEvent((UIViewController *)self,@"viewWillAppear");
}

- (void)viewDidLayoutSubviews{
	%orig;
	BMHandleControllerEvent((UIViewController *)self,@"viewDidLayoutSubviews");
}

%end

%ctor{
	@autoreleasepool{
		[UIDevice currentDevice].batteryMonitoringEnabled=YES;
		__unused static BMBatteryMirrorObserver *observer=nil;
		observer=[[BMBatteryMirrorObserver alloc]init];
	}
}