#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static void *const BMBatteryViewKey = (void *)&BMBatteryViewKey;
static void *const BMManagedBatteryViewKey = (void *)&BMManagedBatteryViewKey;
static void *const BMManagedBatteryViewActiveKey = (void *)&BMManagedBatteryViewActiveKey;
static NSHashTable<UIViewController *> *BMTrackedControllers = nil;

@interface _UIBatteryView : UIView
@property (nonatomic, assign) double chargePercent;
- (instancetype)initWithSizeCategory:(NSInteger)sizeCategory;
- (CGSize)intrinsicContentSize;
- (void)setChargePercent:(double)percent;
- (void)setShowsPercentage:(BOOL)showsPercentage;
- (void)setSaverModeActive:(BOOL)active;
- (void)setFillColor:(UIColor *)color;
- (void)setBodyColor:(UIColor *)color;
- (void)setPinColor:(UIColor *)color;
- (void)setInactiveColor:(UIColor *)color;
@end

static _UIBatteryView *BMBatteryViewForController(UIViewController *controller) {
	return objc_getAssociatedObject(controller, BMBatteryViewKey);
}

static void BMSetBatteryViewForController(UIViewController *controller, _UIBatteryView *batteryView) {
	objc_setAssociatedObject(controller, BMBatteryViewKey, batteryView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

static void BMEnumerateSubviews(UIView *view, void (^block)(UIView *subview)) {
	if (!view || !block) return;
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

static _UIBatteryView *BMEnsureBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (batteryView) return batteryView;

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

// 原作者精确位置逻辑 + 1.37倍放大 + 二级菜单 35.0 坐标
static void BMLayoutBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (!batteryView || !batteryView.superview) return;

	CGRect bounds = controller.view.bounds;
	BOOL isExpanded = CGRectGetHeight(bounds) > 100.0;

	CGSize originalSize = CGSizeZero;
	if ([batteryView respondsToSelector:@selector(intrinsicContentSize)]) {
		originalSize = [batteryView intrinsicContentSize];
	}
	if (originalSize.width <= 0 || originalSize.height <= 0) {
		originalSize = CGSizeMake(27.0, 12.0);
	}

	CGFloat width = originalSize.width;
	CGFloat height = originalSize.height;

	CGFloat x = floor((CGRectGetWidth(bounds) - width) * 0.5);
	CGFloat y;

	if (isExpanded) {
		y = 35.0; // 展开保持 35.0
	} else {
		y = floor((CGRectGetHeight(bounds) - height) * 0.5); // 原作者绝对居中算法
	}

	batteryView.frame = CGRectMake(x, y, width, height);
	batteryView.transform = CGAffineTransformMakeScale(1.37, 1.37);
	[controller.view bringSubviewToFront:batteryView];
}

// 纯原生渲染，绝不干涉 Label
static void BMApplyBatteryStyling(_UIBatteryView *batteryView) {
	if (!batteryView) return;

	UIColor *fillColor = BMManagedBatteryViewFillColor(batteryView);
	UIColor *bodyColor = BMManagedBatteryViewBodyColor(batteryView);
	UIColor *inactiveColor = BMManagedBatteryViewInactiveColor(batteryView);

	if ([batteryView respondsToSelector:@selector(setShowsPercentage:)]) {
		[batteryView setShowsPercentage:YES];
	}
	if ([batteryView respondsToSelector:@selector(setFillColor:)]) {
		[batteryView setFillColor:fillColor];
	}
	if ([batteryView respondsToSelector:@selector(setBodyColor:)]) {
		[batteryView setBodyColor:bodyColor];
	}
	if ([batteryView respondsToSelector:@selector(setPinColor:)]) {
		[batteryView setPinColor:bodyColor];
	}
	if ([batteryView respondsToSelector:@selector(setInactiveColor:)]) {
		[batteryView setInactiveColor:inactiveColor];
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

	if (module && [module respondsToSelector:@selector(isSelected)]) {
		BOOL moduleSelected = ((BOOL (*)(id, SEL))objc_msgSend)(module, @selector(isSelected));
		return moduleSelected || lowPowerModeEnabled;
	}

	return lowPowerModeEnabled;
}

static void BMRefreshLowPowerLabel(UIViewController *controller) {
	if (!controller || !controller.isViewLoaded) return;

	BMSetStockLowPowerArtworkHidden(controller, YES);

	_UIBatteryView *batteryView = BMEnsureBatteryView(controller);
	UIDevice *device = [UIDevice currentDevice];
	device.batteryMonitoringEnabled = YES;
	float batteryLevel = device.batteryLevel;
	BOOL active = BMControllerModuleIsActive(controller);

	if (batteryView) {
		batteryView.hidden = NO;
		batteryView.alpha = 1.0;
		[batteryView setChargePercent:(batteryLevel < 0.0f ? 0.0 : batteryLevel)];
		if ([batteryView respondsToSelector:@selector(setSaverModeActive:)]) {
			[batteryView setSaverModeActive:active];
		}
		BMSetManagedBatteryViewActive(batteryView, active);
		BMApplyBatteryStyling(batteryView);
	}
	BMLayoutBatteryView(controller);
}

static BOOL BMIsLowPowerModuleController(UIViewController *controller) {
	if (!controller) return NO;
	NSString *className = NSStringFromClass(controller.class);
	return [className isEqualToString:@"CCUILowPowerModuleViewController"] ||
		[className containsString:@"LowPowerModuleViewController"];
}

static void BMTrackController(UIViewController *controller) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		BMTrackedControllers = [NSHashTable weakObjectsHashTable];
	});

	if (controller) {
		[BMTrackedControllers addObject:controller];
	}
}

static void BMRefreshTrackedControllers(NSString *reason) {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			BMRefreshTrackedControllers(reason);
		});
		return;
	}

	for (UIViewController *controller in BMTrackedControllers) {
		if (!controller || !controller.isViewLoaded) continue;
		BMRefreshLowPowerLabel(controller);
	}
}

static void BMHandleControllerEvent(UIViewController *controller, NSString *eventName) {
	if (!BMIsLowPowerModuleController(controller) || !controller.isViewLoaded) return;

	BMTrackController(controller);
	BMRefreshLowPowerLabel(controller);
}

@interface BMBatteryMirrorObserver : NSObject
@end

@implementation BMBatteryMirrorObserver

- (instancetype)init {
	self = [super init];
	if (!self) return nil;

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(handlePowerStateChange:) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(handleBatteryChange:) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
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
	BMHandleControllerEvent((UIViewController *)self, @"viewDidLoad");
}

- (void)viewWillAppear:(BOOL)animated {
	%orig(animated);
	BMHandleControllerEvent((UIViewController *)self, @"viewWillAppear");
}

- (void)viewDidLayoutSubviews {
	%orig;
	BMHandleControllerEvent((UIViewController *)self, @"viewDidLayoutSubviews");
}

%end

%ctor {
	@autoreleasepool {
		[UIDevice currentDevice].batteryMonitoringEnabled = YES;
		__unused static BMBatteryMirrorObserver *observer = nil;
		observer = [[BMBatteryMirrorObserver alloc] init];
	}
}
