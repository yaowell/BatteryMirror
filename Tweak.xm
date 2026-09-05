#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

static void *const BMBatteryViewKey = (void *)&BMBatteryViewKey;
static void *const BMOverlayLabelKey = (void *)&BMOverlayLabelKey;
static void *const BMManagedBatteryViewKey = (void *)&BMManagedBatteryViewKey;
static void *const BMManagedBatteryViewActiveKey = (void *)&BMManagedBatteryViewActiveKey;
static NSHashTable<UIViewController *> *BMTrackedControllers = nil;

@interface _UIBatteryView : UIView
@property (nonatomic, assign) double chargePercent;
- (instancetype)initWithSizeCategory:(NSInteger)sizeCategory;
- (void)setChargePercent:(double)percent;
- (void)setChargingState:(NSInteger)state;
- (void)setShowsPercentage:(BOOL)showsPercentage;
- (void)setSaverModeActive:(BOOL)active;
- (void)setInternalSizeCategory:(NSInteger)sizeCategory;
- (void)setFillColor:(UIColor *)color;
- (void)setBodyColor:(UIColor *)color;
- (void)setPinColor:(UIColor *)color;
- (void)setInactiveColor:(UIColor *)color;
- (void)setBoltColor:(UIColor *)color;
@end

@interface CALayer (BatteryMirrorPrivate)
@property (nonatomic, retain) NSString *compositingFilter;
@property (nonatomic, assign) BOOL allowsGroupOpacity;
@property (nonatomic, assign) BOOL allowsGroupBlending;
@end

static _UIBatteryView *BMBatteryViewForController(UIViewController *controller) {
	return objc_getAssociatedObject(controller, BMBatteryViewKey);
}

static UILabel *BMOverlayLabelForBatteryView(_UIBatteryView *batteryView) {
	return objc_getAssociatedObject(batteryView, BMOverlayLabelKey);
}

static void BMSetBatteryViewForController(UIViewController *controller, _UIBatteryView *batteryView) {
	objc_setAssociatedObject(controller, BMBatteryViewKey, batteryView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UILabel *BMEnsureOverlayLabel(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (!batteryView) {
		return nil;
	}

	UILabel *overlayLabel = BMOverlayLabelForBatteryView(batteryView);
	if (overlayLabel) {
		return overlayLabel;
	}

	overlayLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	overlayLabel.userInteractionEnabled = NO;
	overlayLabel.backgroundColor = UIColor.clearColor;
	overlayLabel.textAlignment = NSTextAlignmentCenter;
	overlayLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
	overlayLabel.contentMode = UIViewContentModeCenter;
	overlayLabel.numberOfLines = 1;
	overlayLabel.adjustsFontSizeToFitWidth = NO;

	// 挂载在 batteryView 内部，使其自动响应电池图标的放缩与动画
	[batteryView addSubview:overlayLabel];
	
	objc_setAssociatedObject(batteryView, BMOverlayLabelKey, overlayLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return overlayLabel;
}

static BOOL BMIsManagedBatteryView(_UIBatteryView *batteryView) {
	return [objc_getAssociatedObject(batteryView, BMManagedBatteryViewKey) boolValue];
}

static void BMSetManagedBatteryView(_UIBatteryView *batteryView, BOOL managed) {
	objc_setAssociatedObject(batteryView, BMManagedBatteryViewKey, @(managed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL BMManagedBatteryViewIsActive(_UIBatteryView *batteryView) {
	return [objc_getAssociatedObject(batteryView, BMManagedBatteryViewActiveKey) boolValue];
}

static void BMSetManagedBatteryViewActive(_UIBatteryView *batteryView, BOOL active) {
	objc_setAssociatedObject(batteryView, BMManagedBatteryViewActiveKey, @(active), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL BMManagedBatteryViewIsInLowPowerMode(void) {
	return [NSProcessInfo processInfo].lowPowerModeEnabled;
}

static BOOL BMManagedBatteryViewIsLowLevel(void) {
	float level = [UIDevice currentDevice].batteryLevel;
	return level >= 0.0f && level <= 0.20f;
}

static UIColor *BMManagedBatteryViewBaseColor(_UIBatteryView *batteryView) {
	return BMManagedBatteryViewIsActive(batteryView) ? [UIColor colorWithWhite:0.05 alpha:1.0] : [UIColor colorWithWhite:0.92 alpha:1.0];
}

static UIColor *BMManagedBatteryViewFillColor(_UIBatteryView *batteryView) {
	if (BMManagedBatteryViewIsInLowPowerMode()) {
		return [UIColor colorWithRed:0.96 green:0.82 blue:0.20 alpha:1.0];
	}
	if (BMManagedBatteryViewIsLowLevel()) {
		return [UIColor colorWithRed:0.88 green:0.23 blue:0.19 alpha:1.0];
	}

	return BMManagedBatteryViewBaseColor(batteryView);
}

static UIColor *BMManagedBatteryViewTextColor(_UIBatteryView *batteryView) {
	if (BMManagedBatteryViewIsInLowPowerMode()) {
		return UIColor.blackColor;
	}
	if (BMManagedBatteryViewIsLowLevel()) {
		return UIColor.whiteColor;
	}
	if (BMManagedBatteryViewIsActive(batteryView)) {
		return UIColor.whiteColor;
	}

	return UIColor.blackColor;
}

static UIColor *BMManagedBatteryViewBodyColor(_UIBatteryView *batteryView) {
	return BMManagedBatteryViewBaseColor(batteryView);
}

static UIColor *BMManagedBatteryViewInactiveColor(_UIBatteryView *batteryView) {
	return [BMManagedBatteryViewBaseColor(batteryView) colorWithAlphaComponent:0.34];
}

static NSString *BMManagedBatteryViewDisplayedText(_UIBatteryView *batteryView) {
	float level = [UIDevice currentDevice].batteryLevel;
	NSInteger percent = level < 0.0f ? 0 : (NSInteger)lroundf(level * 100.0f);
	return [NSString stringWithFormat:@"%ld", (long)percent];
}

static UIFont *BMManagedBatteryViewFontToFitWidth(CGFloat targetWidth, CGFloat maxFontSize, NSString *referenceText) {
	if (targetWidth <= 1.0) {
		targetWidth = 18.0;
	}

	CGFloat minFontSize = MAX(8.0, maxFontSize * 0.6);
	UIFont *bestFont = [UIFont boldSystemFontOfSize:minFontSize];
	for (CGFloat fontSize = maxFontSize; fontSize >= minFontSize; fontSize -= 0.5) {
		UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
		CGRect textRect = [referenceText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40.0)
			options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
			attributes:@{ NSFontAttributeName: font }
			context:nil];
		bestFont = font;
		if (ceil(CGRectGetWidth(textRect)) <= targetWidth) {
			break;
		}
	}
	return bestFont;
}

static void BMConfigureOverlayLabel(UILabel *overlayLabel, UIColor *textColor) {
	overlayLabel.textColor = textColor;
	overlayLabel.highlightedTextColor = textColor;
	overlayLabel.tintColor = textColor;
	overlayLabel.shadowColor = UIColor.clearColor;
	overlayLabel.layer.shadowOpacity = 0.0;
	overlayLabel.layer.allowsGroupOpacity = YES;
	overlayLabel.layer.allowsGroupBlending = NO;
	overlayLabel.layer.compositingFilter = nil;
}

static void BMEnumerateSubviews(UIView *view, void (^block)(UIView *subview)) {
	if (!view || !block) {
		return;
	}

	block(view);
	for (UIView *subview in view.subviews) {
		BMEnumerateSubviews(subview, block);
	}
}

static void BMSetStockLowPowerArtworkHidden(UIViewController *controller, BOOL hidden) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	BMEnumerateSubviews(controller.view, ^(UIView *subview) {
		if (subview == batteryView || (batteryView && [subview isDescendantOfView:batteryView])) {
			return;
		}

		NSString *className = NSStringFromClass(subview.class);
		if ([subview isKindOfClass:[UIImageView class]] || [className containsString:@"CCUICAPackageView"]) {
			subview.hidden = hidden;
			subview.alpha = hidden ? 0.0 : 1.0;
		}
	});
}

static void BMHideStockLowPowerArtwork(UIViewController *controller) {
	BMSetStockLowPowerArtworkHidden(controller, YES);
}

static BOOL BMIsLowPowerModuleController(UIViewController *controller) {
	if (!controller) {
		return NO;
	}

	NSString *className = NSStringFromClass(controller.class);
	if ([className containsString:@"LowPower"]) {
		return YES;
	}

	id module = nil;
	@try {
		module = [controller valueForKey:@"module"];
	} @catch (__unused NSException *exception) {
		module = nil;
	}

	if (module) {
		NSString *moduleClassName = NSStringFromClass([module class]);
		if ([moduleClassName containsString:@"LowPower"]) {
			return YES;
		}
	}

	return NO;
}

static _UIBatteryView *BMEnsureBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (batteryView) {
		return batteryView;
	}

	Class batteryViewClass = objc_getClass("_UIBatteryView");
	if (!batteryViewClass || ![batteryViewClass instancesRespondToSelector:@selector(initWithSizeCategory:)]) {
		return nil;
	}

	batteryView = [(_UIBatteryView *)[batteryViewClass alloc] initWithSizeCategory:0];
	batteryView.userInteractionEnabled = NO;
	[controller.view addSubview:batteryView];
	BMSetBatteryViewForController(controller, batteryView);
	BMSetManagedBatteryView(batteryView, YES);

	return batteryView;
}

// 核心修正 1：完美解决图标在卡片内居中的绝对数学对齐
static void BMLayoutBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (!batteryView || !batteryView.superview) {
		return;
	}

	UIView *targetContainer = controller.view;
	CGRect targetBounds = targetContainer.bounds;

	CGFloat centerX = CGRectGetMidX(targetBounds);
	CGFloat centerY = CGRectGetMidY(targetBounds);

	// 如果卡片高度大于宽度的 1.2 倍（例如展开态或长条形态），图标精准锁定在顶部 W x W 正方形区域的中心
	if (CGRectGetHeight(targetBounds) > CGRectGetWidth(targetBounds) * 1.2) {
		centerY = CGRectGetWidth(targetBounds) * 0.5;
	}

	CGPoint absoluteCenter = CGPointMake(centerX, centerY);

	batteryView.transform = CGAffineTransformIdentity;
	batteryView.bounds = CGRectMake(0, 0, 31.0, 16.0);
	batteryView.center = absoluteCenter;
	
	// 保持 1.40 倍放大的几何要求
	batteryView.transform = CGAffineTransformMakeScale(1.40, 1.40);
	[targetContainer bringSubviewToFront:batteryView];

	// 核心修正 2：扣除极针（Pin），把 Label 的几何中心强制打在电池的主体中心 (14.0, 8.0)
	UILabel *overlayLabel = BMOverlayLabelForBatteryView(batteryView);
	if (overlayLabel) {
		if (overlayLabel.superview != batteryView) {
			[overlayLabel removeFromSuperview];
			[batteryView addSubview:overlayLabel];
		}
		
		overlayLabel.transform = CGAffineTransformIdentity;
		// 电池总宽 31pt，右侧 Pin 占用 3pt，主体宽 28pt
		overlayLabel.bounds = CGRectMake(0, 0, 28.0, 16.0);
		overlayLabel.center = CGPointMake(14.0, 8.0);
		[batteryView bringSubviewToFront:overlayLabel];
	}
}

static void BMSetManagedBatteryVisibility(_UIBatteryView *batteryView, BOOL visible) {
	if (!batteryView) {
		return;
	}

	batteryView.hidden = !visible;
	batteryView.alpha = visible ? 1.0 : 0.0;

	UILabel *overlayLabel = BMOverlayLabelForBatteryView(batteryView);
	if (overlayLabel) {
		overlayLabel.hidden = !visible || overlayLabel.attributedText.length == 0;
		overlayLabel.alpha = visible ? 1.0 : 0.0;
	}
}

// 核心修正 3：样式渲染与 11.1pt 基准字号对齐
static void BMApplyBatteryStyling(_UIBatteryView *batteryView) {
	if (!batteryView) {
		return;
	}

	UIColor *fillColor = BMManagedBatteryViewFillColor(batteryView);
	UIColor *bodyColor = BMManagedBatteryViewBodyColor(batteryView);
	UIColor *inactiveColor = BMManagedBatteryViewInactiveColor(batteryView);
	UIColor *pinColor = bodyColor;

	if ([batteryView respondsToSelector:@selector(setInternalSizeCategory:)]) {
		[batteryView setInternalSizeCategory:1];
	}
	if ([batteryView respondsToSelector:@selector(setFillColor:)]) {
		[batteryView setFillColor:fillColor];
	}
	if ([batteryView respondsToSelector:@selector(setBodyColor:)]) {
		[batteryView setBodyColor:bodyColor];
	}
	if ([batteryView respondsToSelector:@selector(setPinColor:)]) {
		[batteryView setPinColor:pinColor];
	}
	if ([batteryView respondsToSelector:@selector(setInactiveColor:)]) {
		[batteryView setInactiveColor:inactiveColor];
	}
	if ([batteryView respondsToSelector:@selector(setBoltColor:)]) {
		[batteryView setBoltColor:fillColor];
	}

	// 隐藏系统可能自带的 UILabel
	for (UIView *subview in batteryView.subviews) {
		if ([subview isKindOfClass:[UILabel class]]) {
			UILabel *label = (UILabel *)subview;
			UILabel *overlayLabel = BMOverlayLabelForBatteryView(batteryView);
			if (label != overlayLabel) {
				label.hidden = YES;
				label.alpha = 0.0;
			}
		}
	}

	UIResponder *responder = batteryView.nextResponder;
	while (responder && ![responder isKindOfClass:[UIViewController class]]) {
		responder = responder.nextResponder;
	}
	UIViewController *controller = (UIViewController *)responder;
	if (!controller) {
		return;
	}

	UILabel *overlayLabel = BMEnsureOverlayLabel(controller);
	NSString *displayText = BMManagedBatteryViewDisplayedText(batteryView);

	if (displayText.length > 0) {
		CGFloat maxFontSize = 11.1; 
		UIColor *textColor = BMManagedBatteryViewTextColor(batteryView);
		UIFont *normalFont = BMManagedBatteryViewFontToFitWidth(28.0, maxFontSize, @"100");
		
		BMConfigureOverlayLabel(overlayLabel, textColor);
		overlayLabel.font = normalFont;
		
		overlayLabel.transform = CGAffineTransformIdentity;
		overlayLabel.bounds = CGRectMake(0, 0, 28.0, 16.0);
		overlayLabel.center = CGPointMake(14.0, 8.0);

		overlayLabel.attributedText = [[NSAttributedString alloc] initWithString:displayText attributes:@{
			NSForegroundColorAttributeName: textColor,
			NSFontAttributeName: normalFont
		}];
		overlayLabel.hidden = NO;
		overlayLabel.alpha = 1.0;
		[batteryView bringSubviewToFront:overlayLabel];
	} else {
		overlayLabel.bounds = CGRectZero;
		overlayLabel.attributedText = nil;
		overlayLabel.hidden = YES;
		overlayLabel.alpha = 0.0;
	}
}

static BOOL BMControllerModuleIsActive(UIViewController *controller) {
	BOOL lowPowerModeEnabled = [NSProcessInfo processInfo].lowPowerModeEnabled;
	id module = nil;
	@try {
		module = [controller valueForKey:@"module"];
	} @catch (__unused NSException *exception) {
		module = nil;
	}

	if ([module respondsToSelector:@selector(isSelected)]) {
		BOOL moduleSelected = ((BOOL (*)(id, SEL))objc_msgSend)(module, @selector(isSelected));
		return moduleSelected || lowPowerModeEnabled;
	}

	return lowPowerModeEnabled;
}

static void BMRefreshLowPowerLabel(UIViewController *controller) {
	if (!BMIsLowPowerModuleController(controller)) {
		return;
	}

	BMHideStockLowPowerArtwork(controller);

	_UIBatteryView *batteryView = BMEnsureBatteryView(controller);
	BOOL showsPercentage = YES;
	UIDevice *device = [UIDevice currentDevice];
	device.batteryMonitoringEnabled = YES;
	float batteryLevel = device.batteryLevel;
	
	NSInteger chargingState = 0; 
	BOOL active = BMControllerModuleIsActive(controller);
	if (batteryView) {
		BMSetManagedBatteryVisibility(batteryView, YES);
		[batteryView setChargePercent:(batteryLevel < 0.0f ? 0.0 : batteryLevel)];
		if ([batteryView respondsToSelector:@selector(setChargingState:)]) {
			[batteryView setChargingState:chargingState];
		}
		if ([batteryView respondsToSelector:@selector(setSaverModeActive:)]) {
			[batteryView setSaverModeActive:active];
		}
		if ([batteryView respondsToSelector:@selector(setShowsPercentage:)]) {
			[batteryView setShowsPercentage:showsPercentage];
		}
		BMSetManagedBatteryViewActive(batteryView, active);
		BMApplyBatteryStyling(batteryView);
	}
	BMLayoutBatteryView(controller);
}

static void BMTrackController(UIViewController *controller) {
	if (!BMIsLowPowerModuleController(controller)) {
		return;
	}

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		BMTrackedControllers = [NSHashTable weakObjectsHashTable];
	});

	[BMTrackedControllers addObject:controller];
}

static void BMRefreshTrackedControllers(NSString *reason) {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			BMRefreshTrackedControllers(reason);
		});
		return;
	}

	for (UIViewController *controller in BMTrackedControllers) {
		if (!controller || !controller.isViewLoaded) {
			continue;
		}

		BMRefreshLowPowerLabel(controller);
	}
}

static void BMHandleControllerEvent(UIViewController *controller) {
	if (!controller || !controller.isViewLoaded) {
		return;
	}

	if (!BMIsLowPowerModuleController(controller)) {
		return;
	}

	BMTrackController(controller);
	BMRefreshLowPowerLabel(controller);
}

@interface BMBatteryMirrorObserver : NSObject
@end

@implementation BMBatteryMirrorObserver

- (instancetype)init {
	self = [super init];
	if (!self) {
		return nil;
	}

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(handlePowerStateChange:) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(handleBatteryChange:) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(handleBatteryChange:) name:UIDeviceBatteryStateDidChangeNotification object:nil];
	return self;
}

- (void)handlePowerStateChange:(NSNotification *)notification {
	BMRefreshTrackedControllers(notification.name);
}

- (void)handleBatteryChange:(NSNotification *)notification {
	BMRefreshTrackedControllers(notification.name);
}

@end

%hook _UIBatteryView

- (void)layoutSubviews {
	%orig;

	if (BMIsManagedBatteryView(self)) {
		BMApplyBatteryStyling(self);
	}
}

- (UIColor *)_batteryFillColor {
	if (BMIsManagedBatteryView(self)) {
		return BMManagedBatteryViewFillColor(self);
	}

	return %orig;
}

- (UIColor *)_batteryTextColor {
	if (BMIsManagedBatteryView(self)) {
		return BMManagedBatteryViewTextColor(self);
	}

	return %orig;
}

- (UIColor *)_batteryUnfilledColor {
	if (BMIsManagedBatteryView(self)) {
		return BMManagedBatteryViewInactiveColor(self);
	}

	return %orig;
}

- (UIColor *)bodyColor {
	if (BMIsManagedBatteryView(self)) {
		return BMManagedBatteryViewBodyColor(self);
	}

	return %orig;
}

- (UIColor *)pinColor {
	if (BMIsManagedBatteryView(self)) {
		return BMManagedBatteryViewBodyColor(self);
	}

	return %orig;
}

%end

%hook UIViewController

- (void)viewDidLoad {
	%orig;
	BMHandleControllerEvent(self);
}

- (void)viewWillAppear:(BOOL)animated {
	%orig(animated);
	BMHandleControllerEvent(self);
}

- (void)viewDidLayoutSubviews {
	%orig;
	BMHandleControllerEvent(self);
}

%end

%ctor {
	@autoreleasepool {
		[UIDevice currentDevice].batteryMonitoringEnabled = YES;
		__unused static BMBatteryMirrorObserver *observer = nil;
		observer = [[BMBatteryMirrorObserver alloc] init];
	}
}
