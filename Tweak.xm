#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

extern NSString *const kCAFilterDestOut;

static void *const BMBatteryViewKey = (void *)&BMBatteryViewKey;
static void *const BMBoltImageViewKey = (void *)&BMBoltImageViewKey;
static void *const BMOverlayLabelKey = (void *)&BMOverlayLabelKey;
static void *const BMOverlayBoltImageViewKey = (void *)&BMOverlayBoltImageViewKey;
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
- (UIColor *)_batteryFillColor;
- (UIColor *)_batteryUnfilledColor;
- (UIColor *)_batteryTextColor;
- (UIColor *)bodyColor;
- (UIColor *)pinColor;
- (void)setBodyColorAlpha:(double)alpha;
- (void)setPinColorAlpha:(double)alpha;
@end

@interface CALayer (BatteryMirrorPrivate)
@property (nonatomic, retain) NSString *compositingFilter;
@property (nonatomic, assign) BOOL allowsGroupOpacity;
@property (nonatomic, assign) BOOL allowsGroupBlending;
@end

static _UIBatteryView *BMBatteryViewForController(UIViewController *controller) {
	return objc_getAssociatedObject(controller, BMBatteryViewKey);
}

static UIImageView *BMBoltImageViewForBatteryView(_UIBatteryView *batteryView) {
	return objc_getAssociatedObject(batteryView, BMBoltImageViewKey);
}

static UILabel *BMOverlayLabelForBatteryView(_UIBatteryView *batteryView) {
	return objc_getAssociatedObject(batteryView, BMOverlayLabelKey);
}

static UIImageView *BMOverlayBoltImageViewForBatteryView(_UIBatteryView *batteryView) {
	return objc_getAssociatedObject(batteryView, BMOverlayBoltImageViewKey);
}

static void BMSetBatteryViewForController(UIViewController *controller, _UIBatteryView *batteryView) {
	objc_setAssociatedObject(controller, BMBatteryViewKey, batteryView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIImageView *BMEnsureBoltImageView(_UIBatteryView *batteryView) {
	UIImageView *boltImageView = BMBoltImageViewForBatteryView(batteryView);
	if (boltImageView) {
		return boltImageView;
	}

	boltImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	boltImageView.userInteractionEnabled = NO;
	boltImageView.contentMode = UIViewContentModeScaleAspectFit;
	boltImageView.hidden = YES;
	[batteryView addSubview:boltImageView];
	objc_setAssociatedObject(batteryView, BMBoltImageViewKey, boltImageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return boltImageView;
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

static UIImageView *BMEnsureOverlayBoltImageView(_UIBatteryView *batteryView) {
	UIImageView *overlayBoltImageView = BMOverlayBoltImageViewForBatteryView(batteryView);
	if (overlayBoltImageView) {
		return overlayBoltImageView;
	}

	overlayBoltImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	overlayBoltImageView.userInteractionEnabled = NO;
	overlayBoltImageView.contentMode = UIViewContentModeScaleAspectFit;
	overlayBoltImageView.hidden = YES;
	[batteryView addSubview:overlayBoltImageView];
	objc_setAssociatedObject(batteryView, BMOverlayBoltImageViewKey, overlayBoltImageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return overlayBoltImageView;
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

static BOOL BMManagedBatteryViewUsesCutoutText(_UIBatteryView *batteryView) {
	(void)batteryView;
	return NO;
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

static void BMConfigureOverlayLabel(UILabel *overlayLabel, UIColor *textColor, BOOL useCutoutText) {
	overlayLabel.textColor = textColor;
	overlayLabel.highlightedTextColor = textColor;
	overlayLabel.tintColor = textColor;
	overlayLabel.shadowColor = UIColor.clearColor;
	overlayLabel.layer.shadowOpacity = 0.0;
	overlayLabel.layer.allowsGroupOpacity = YES;
	overlayLabel.layer.allowsGroupBlending = NO;
	overlayLabel.layer.compositingFilter = useCutoutText ? kCAFilterDestOut : nil;
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

static void BMLayoutBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (!batteryView || !batteryView.superview) {
		return;
	}

	CGRect bounds = controller.view.bounds;
	CGFloat viewWidth = CGRectGetWidth(bounds);
	CGFloat viewHeight = CGRectGetHeight(bounds);

	if (viewWidth <= 0 || viewHeight <= 0) return;

	CGFloat width = 31.0;
	CGFloat height = 16.0;

	CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
	CGFloat baseScale = 1.25;

	if (screenWidth >= 420.0) {
		baseScale = 1.35;
	} else if (screenWidth < 380.0) {
		baseScale = 1.15;
	}

	CGFloat x = floor((viewWidth - width) * 0.5);

	BOOL isExpandedMenu = viewHeight > 120.0;
	CGFloat yRatio = isExpandedMenu ? 0.25 : 0.50;
	CGFloat y = floor(viewHeight * yRatio - height * 0.5);

	batteryView.frame = CGRectMake(x, y, width, height);
	batteryView.transform = CGAffineTransformMakeScale(baseScale, baseScale);

	[controller.view bringSubviewToFront:batteryView];
}

// 递归解锁所有 Layer 层的 masksToBounds，确保右侧 Pin 和 Body 绝对不被切断
static void BMUnlockLayerClipping(CALayer *layer) {
	if (!layer) return;
	layer.masksToBounds = NO;
	for (CALayer *sublayer in layer.sublayers) {
		BMUnlockLayerClipping(sublayer);
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

	UIImageView *overlayBoltImageView = BMOverlayBoltImageViewForBatteryView(batteryView);
	if (overlayBoltImageView) {
		overlayBoltImageView.hidden = YES;
		overlayBoltImageView.alpha = 0.0;
	}
}

static void BMApplyBatteryStyling(_UIBatteryView *batteryView) {
	if (!batteryView) {
		return;
	}

	UIColor *fillColor = BMManagedBatteryViewFillColor(batteryView);
	UIColor *bodyColor = BMManagedBatteryViewBodyColor(batteryView);
	UIColor *inactiveColor = BMManagedBatteryViewInactiveColor(batteryView);
	UIColor *pinColor = bodyColor;

	// 强制电池主视图以及所有子图层不切边
	batteryView.clipsToBounds = NO;
	BMUnlockLayerClipping(batteryView.layer);

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
	if ([batteryView respondsToSelector:@selector(setBodyColorAlpha:)]) {
		[batteryView setBodyColorAlpha:1.0];
	}
	if ([batteryView respondsToSelector:@selector(setPinColorAlpha:)]) {
		[batteryView setPinColorAlpha:1.0];
	}

	BMEnumerateSubviews(batteryView, ^(UIView *subview) {
		if ([subview isKindOfClass:[UILabel class]]) {
			UILabel *label = (UILabel *)subview;
			UILabel *overlayLabel = BMEnsureOverlayLabel(batteryView);
			UIImageView *overlayBoltImageView = BMEnsureOverlayBoltImageView(batteryView);
			if (label == overlayLabel) {
				return;
			}

			UIImageView *boltImageView = BMEnsureBoltImageView(batteryView);
			label.hidden = YES;
			label.alpha = 0.0;
			boltImageView.hidden = YES;

			NSString *displayText = BMManagedBatteryViewDisplayedText(batteryView, label);

			if (displayText.length > 0) {
				UIColor *textColor = BMManagedBatteryViewTextColor(batteryView);
				BOOL useCutoutText = BMManagedBatteryViewUsesCutoutText(batteryView);

				// 精准紧凑字号：两位数 9.0pt，三位数 7.5pt
				UIFont *font = [UIFont boldSystemFontOfSize:(displayText.length >= 3 ? 7.5 : 9.0)];

				BMConfigureOverlayLabel(overlayLabel, textColor, useCutoutText);
				overlayLabel.font = font;

				// 核心修复：电池内主体框长 27px，除去右侧 Pin 角 4px，有效居中区域为 x: 0 ~ 27。
				// 强制 Label 在 (0, 0, 27, 16) 内精确居中，绝不借用原生 Label 的偏右坐标！
				overlayLabel.frame = CGRectMake(0.0, 0.0, 27.0, 16.0);
				overlayLabel.attributedText = [[NSAttributedString alloc] initWithString:displayText attributes:@{
					NSForegroundColorAttributeName: textColor,
					NSFontAttributeName: font
				}];
				overlayLabel.hidden = NO;
				overlayLabel.alpha = 1.0;
				overlayLabel.transform = CGAffineTransformIdentity;

				overlayBoltImageView.hidden = YES;
				overlayBoltImageView.alpha = 0.0;
				overlayBoltImageView.transform = CGAffineTransformIdentity;
				[batteryView bringSubviewToFront:overlayLabel];
			} else {
				overlayLabel.attributedText = nil;
				overlayLabel.hidden = YES;
				overlayLabel.alpha = 0.0;
				overlayLabel.transform = CGAffineTransformIdentity;
				overlayBoltImageView.hidden = YES;
				overlayBoltImageView.alpha = 0.0;
				overlayBoltImageView.transform = CGAffineTransformIdentity;
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

	if ([module respondsToSelector:@selector(isSelected)]) {
		BOOL moduleSelected = ((BOOL (*)(id, SEL))objc_msgSend)(module, @selector(isSelected));
		return moduleSelected || lowPowerModeEnabled;
	}

	return lowPowerModeEnabled;
}

static void BMRefreshLowPowerLabel(UIViewController *controller) {
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

static BOOL BMIsLowPowerModuleController(UIViewController *controller) {
	NSString *className = NSStringFromClass(controller.class);
	return [className isEqualToString:@"CCUILowPowerModuleViewController"] ||
		[className containsString:@"LowPowerModuleViewController"];
}

static void BMTrackController(UIViewController *controller) {
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
