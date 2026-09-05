#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

extern NSString *const kCAFilterDestOut;

static void *const BMBatteryViewKey = (void *)&BMBatteryViewKey;
static void *const BMOverlayLabelKey = (void *)&BMOverlayLabelKey;
static void *const BMLabelContainerFrameKey = (void *)&BMLabelContainerFrameKey;
static void *const BMManagedBatteryViewKey = (void *)&BMManagedBatteryViewKey;
static void *const BMManagedBatteryViewActiveKey = (void *)&BMManagedBatteryViewActiveKey;
static NSHashTable<UIViewController *> *BMTrackedControllers = nil;

@interface _UIBatteryView : UIView
@property (nonatomic, assign) double chargePercent;
- (instancetype)initWithSizeCategory:(NSInteger)sizeCategory;
- (void)setChargePercent:(double)percent;
- (void)setShowsPercentage:(BOOL)showsPercentage;
- (void)setSaverModeActive:(BOOL)active;
- (void)setFillColor:(UIColor *)color;
- (void)setBodyColor:(UIColor *)color;
- (void)setPinColor:(UIColor *)color;
- (void)setInactiveColor:(UIColor *)color;
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

static UILabel *BMEnsureOverlayLabel(_UIBatteryView *batteryView) {
	UILabel *overlayLabel = BMOverlayLabelForBatteryView(batteryView);
	if (overlayLabel) {
		return overlayLabel;
	}

	overlayLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	overlayLabel.userInteractionEnabled = NO;
	overlayLabel.backgroundColor = UIColor.clearColor;
	overlayLabel.textAlignment = NSTextAlignmentCenter;
	overlayLabel.numberOfLines = 1;
	overlayLabel.adjustsFontSizeToFitWidth = NO;
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

static NSString *BMManagedBatteryViewDisplayedText(_UIBatteryView *batteryView, UILabel *label) {
	float level = [UIDevice currentDevice].batteryLevel;
	NSInteger percent = level < 0.0f ? 0 : (NSInteger)lroundf(level * 100.0f);
	return [NSString stringWithFormat:@"%ld", (long)percent];
}

// 修复 100 骑框的核心函数：加入了 safeTargetWidth 安全防护
static UIFont *BMManagedBatteryViewFontToFitWidth(CGFloat targetWidth, CGFloat maxFontSize, NSString *referenceText) {
	if (targetWidth <= 1.0) {
		targetWidth = 18.0;
	}

	// 关键防护：强行给可绘制区间扣除 2.5pt 的安全 Padding，防止 100 溢出踩踏右外框
	CGFloat safeTargetWidth = targetWidth - 3.0;

	CGFloat minFontSize = MAX(8.0, maxFontSize * 0.6);
	UIFont *bestFont = [UIFont boldSystemFontOfSize:minFontSize];
	for (CGFloat fontSize = maxFontSize; fontSize >= minFontSize; fontSize -= 0.5) {
		UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
		CGRect textRect = [referenceText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40.0)
			options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
			attributes:@{ NSFontAttributeName: font }
			context:nil];
		bestFont = font;
		if (ceil(CGRectGetWidth(textRect)) <= safeTargetWidth) {
			break;
		}
	}
	return bestFont;
}

static CGFloat BMOverlayExtraWidth(void) {
	return 11.0;
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

// 布局逻辑：1.37 倍物理拉伸与双轴精准居中
static void BMLayoutBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (!batteryView || !batteryView.superview) {
		return;
	}

	CGRect bounds = controller.view.bounds;
	BOOL isExpanded = CGRectGetHeight(bounds) > 100.0;
	
	CGFloat width = 31.0;
	CGFloat height = 16.0;
	
	CGFloat x = floor((CGRectGetWidth(bounds) - width) * 0.5);
	CGFloat y;

	if (isExpanded) {
		y = 35.0; 
	} else {
		y = floor((CGRectGetHeight(bounds) - height) * 0.5);
	}

	batteryView.frame = CGRectMake(x, y, width, height);
	batteryView.transform = CGAffineTransformMakeScale(1.37, 1.37);
	[controller.view bringSubviewToFront:batteryView];
}

static void BMApplyBatteryStyling(_UIBatteryView *batteryView) {
	if (!batteryView) {
		return;
	}

	UIColor *fillColor = BMManagedBatteryViewFillColor(batteryView);
	UIColor *bodyColor = BMManagedBatteryViewBodyColor(batteryView);
	UIColor *inactiveColor = BMManagedBatteryViewInactiveColor(batteryView);

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

	BMEnumerateSubviews(batteryView, ^(UIView *subview) {
		if ([subview isKindOfClass:[UILabel class]]) {
			UILabel *label = (UILabel *)subview;
			UILabel *overlayLabel = BMEnsureOverlayLabel(batteryView);
			if (label == overlayLabel) {
				return;
			}

			CGRect containerFrame = label.frame;
			if (CGRectGetWidth(containerFrame) <= 1.0 || CGRectGetHeight(containerFrame) <= 1.0) {
				containerFrame = CGRectMake(2.0, 2.0, 27.0, 12.0);
			} else if (!objc_getAssociatedObject(label, BMLabelContainerFrameKey)) {
				objc_setAssociatedObject(label, BMLabelContainerFrameKey, [NSValue valueWithCGRect:containerFrame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			} else {
				containerFrame = [objc_getAssociatedObject(label, BMLabelContainerFrameKey) CGRectValue];
			}

			CGFloat overlayWidth = CGRectGetWidth(containerFrame) + BMOverlayExtraWidth();
			CGFloat overlayOriginX = CGRectGetMidX(containerFrame) - (overlayWidth * 0.5);
			CGFloat maxFontSize = label.font.pointSize > 0 ? (label.font.pointSize + 7.0) : 14.0;
			UIColor *textColor = BMManagedBatteryViewTextColor(batteryView);
			NSString *displayText = BMManagedBatteryViewDisplayedText(batteryView, label);

			label.hidden = YES;
			label.alpha = 0.0;

			if (displayText.length > 0) {
				UIFont *normalFont = BMManagedBatteryViewFontToFitWidth(overlayWidth, maxFontSize, @"100");
				BMConfigureOverlayLabel(overlayLabel, textColor);
				overlayLabel.font = normalFont;
				overlayLabel.frame = CGRectMake(overlayOriginX, CGRectGetMinY(containerFrame), overlayWidth, CGRectGetHeight(containerFrame));
				overlayLabel.text = displayText;
				overlayLabel.hidden = NO;
				overlayLabel.alpha = 1.0;
				overlayLabel.transform = CGAffineTransformIdentity;
				[batteryView bringSubviewToFront:overlayLabel];
			} else {
				overlayLabel.frame = containerFrame;
				overlayLabel.text = nil;
				overlayLabel.hidden = YES;
				overlayLabel.alpha = 0.0;
			}
		}
	});
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
	if (!controller || !controller.isViewLoaded) {
		return;
	}

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
		if ([batteryView respondsToSelector:@selector(setShowsPercentage:)]) {
			[batteryView setShowsPercentage:YES];
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
		if (!controller || !controller.isViewLoaded) {
			continue;
		}

		BMRefreshLowPowerLabel(controller);
	}
}

static void BMHandleControllerEvent(UIViewController *controller, NSString *eventName) {
	if (!BMIsLowPowerModuleController(controller) || !controller.isViewLoaded) {
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
