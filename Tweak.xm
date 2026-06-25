#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

extern NSString *const kCAFilterDestOut;

static CFStringRef const BMSpringBoardPreferencesDomain = CFSTR("com.apple.springboard");
static CFStringRef const BMPrefsDomain = CFSTR("com.futur3sn0w.batterymirror.preferences");
static CFStringRef const BMPrefsReloadNotification = CFSTR("com.futur3sn0w.batterymirror/ReloadPrefs");
static void *const BMBatteryViewKey = (void *)&BMBatteryViewKey;
static void *const BMBoltImageViewKey = (void *)&BMBoltImageViewKey;
static void *const BMOverlayLabelKey = (void *)&BMOverlayLabelKey;
static void *const BMOverlayBoltImageViewKey = (void *)&BMOverlayBoltImageViewKey;
static void *const BMLabelContainerFrameKey = (void *)&BMLabelContainerFrameKey;
static void *const BMManagedBatteryViewKey = (void *)&BMManagedBatteryViewKey;
static void *const BMManagedBatteryViewActiveKey = (void *)&BMManagedBatteryViewActiveKey;
static NSString *const BMLogPath = @"/var/mobile/Documents/BatteryMirror-log.txt";
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

static void BMWriteLogLine(NSString *line) {
	(void)line;
}

static BOOL BMBatteryPercentageEnabled(void) {
	CFPropertyListRef value = CFPreferencesCopyValue(CFSTR("SBShowBatteryPercentage"), BMSpringBoardPreferencesDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	id bridgedValue = CFBridgingRelease(value);
	if ([bridgedValue respondsToSelector:@selector(boolValue)]) {
		return [bridgedValue boolValue];
	}

	return NO;
}

static id BMPrefsValue(CFStringRef key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue(key, BMPrefsDomain));
}

static BOOL BMPrefsEnabled(void) {
	id value = BMPrefsValue(CFSTR("Enabled"));
	if ([value respondsToSelector:@selector(boolValue)]) {
		return [value boolValue];
	}

	return YES;
}

static CGFloat BMPrefsCornerRadius(void) {
	id value = BMPrefsValue(CFSTR("CornerRadius"));
	CGFloat radius = [value respondsToSelector:@selector(doubleValue)] ? (CGFloat)[value doubleValue] : 4.0;
	return MAX(0.0, MIN(radius, 8.0));
}

static BOOL BMPrefsShowsNub(void) {
	id value = BMPrefsValue(CFSTR("ShowsNub"));
	if ([value respondsToSelector:@selector(boolValue)]) {
		return [value boolValue];
	}

	return YES;
}

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

static BOOL BMManagedBatteryViewIsCharging(void) {
	UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
	return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
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
	if (BMManagedBatteryViewIsCharging()) {
		return [UIColor colorWithRed:0.30 green:0.88 blue:0.44 alpha:1.0];
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
	if (BMManagedBatteryViewIsCharging() || BMManagedBatteryViewIsLowLevel()) {
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
	if (!BMBatteryPercentageEnabled()) {
		return label.text;
	}

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

static UIFont *BMManagedBatteryViewVariableWidthFont(UIFont *baseFont, CGFloat fontSize, CGFloat widthTrait) {
	if (!baseFont) {
		baseFont = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
	}

	baseFont = [baseFont fontWithSize:fontSize];
	NSMutableDictionary *traits = [NSMutableDictionary dictionary];
	NSDictionary *existingTraits = [baseFont.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
	if ([existingTraits isKindOfClass:[NSDictionary class]]) {
		[traits addEntriesFromDictionary:existingTraits];
	}
	traits[UIFontWidthTrait] = @(widthTrait);
	UIFontDescriptor *descriptor = [baseFont.fontDescriptor fontDescriptorByAddingAttributes:@{
		UIFontDescriptorTraitsAttribute: traits
	}];
	UIFont *font = [UIFont fontWithDescriptor:descriptor size:fontSize];
	return font ?: baseFont;
}

static UIFont *BMManagedBatteryViewInterpolatedFontToFitWidth(UIFont *baseFont, CGFloat targetWidth, CGFloat maxFontSize, NSString *referenceText, CGFloat *resolvedWidthTrait) {
	if (targetWidth <= 1.0) {
		targetWidth = 18.0;
	}

	CGFloat minFontSize = MAX(8.0, maxFontSize * 0.6);
	CGFloat bestWidthTrait = 0.0;
	UIFont *bestFont = BMManagedBatteryViewVariableWidthFont(baseFont, minFontSize, bestWidthTrait);
	for (CGFloat fontSize = maxFontSize; fontSize >= minFontSize; fontSize -= 0.5) {
		for (CGFloat widthTrait = 0.0; widthTrait >= -0.40; widthTrait -= 0.04) {
			UIFont *font = BMManagedBatteryViewVariableWidthFont(baseFont, fontSize, widthTrait);
			CGRect textRect = [referenceText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40.0)
				options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
				attributes:@{ NSFontAttributeName: font }
				context:nil];
			bestFont = font;
			bestWidthTrait = widthTrait;
			if (ceil(CGRectGetWidth(textRect)) <= targetWidth) {
				if (resolvedWidthTrait) {
					*resolvedWidthTrait = bestWidthTrait;
				}
				return bestFont;
			}
		}
	}
	if (resolvedWidthTrait) {
		*resolvedWidthTrait = bestWidthTrait;
	}
	return bestFont;
}

static CGFloat BMOverlayExtraWidth(void) {
	return 11.0;
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

static NSString *BMColorDescription(UIColor *color) {
	if (!color) {
		return @"(null)";
	}

	CGFloat red = 0.0;
	CGFloat green = 0.0;
	CGFloat blue = 0.0;
	CGFloat alpha = 0.0;
	if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
		return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)", red, green, blue, alpha];
	}

	return color.description;
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

static void BMLogBatteryMethodSurveyIfNeeded(void) {
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

static void BMShowStockLowPowerArtwork(UIViewController *controller) {
	BMSetStockLowPowerArtworkHidden(controller, NO);
}

static _UIBatteryView *BMEnsureBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (batteryView) {
		return batteryView;
	}

	Class batteryViewClass = objc_getClass("_UIBatteryView");
	if (!batteryViewClass || ![batteryViewClass instancesRespondToSelector:@selector(initWithSizeCategory:)]) {
		BMWriteLogLine(@"Unable to create _UIBatteryView; class or selector missing");
		return nil;
	}

	batteryView = [(_UIBatteryView *)[batteryViewClass alloc] initWithSizeCategory:0];
	batteryView.userInteractionEnabled = NO;
	[controller.view addSubview:batteryView];
	BMSetBatteryViewForController(controller, batteryView);
	BMSetManagedBatteryView(batteryView, YES);
	BMWriteLogLine([NSString stringWithFormat:@"Created _UIBatteryView for controller=%@", NSStringFromClass(controller.class)]);

	return batteryView;
}

static void BMLayoutBatteryView(UIViewController *controller) {
	_UIBatteryView *batteryView = BMBatteryViewForController(controller);
	if (!batteryView || !batteryView.superview) {
		return;
	}

	CGRect bounds = controller.view.bounds;
	CGFloat width = MIN(CGRectGetWidth(bounds) - 8.0, 31.0);
	CGFloat height = 16.0;
	CGFloat x = floor((CGRectGetWidth(bounds) - width) * 0.5);
	CGFloat y = floor(CGRectGetHeight(bounds) * 0.505 - height * 0.5);
	batteryView.frame = CGRectMake(x, y, width, height);
	batteryView.transform = CGAffineTransformMakeScale(1.18, 1.18);
	[controller.view bringSubviewToFront:batteryView];
}

static BOOL BMShouldRoundBatteryLayer(CALayer *layer) {
	if (!layer) {
		return NO;
	}

	CGRect bounds = layer.bounds;
	CGFloat width = CGRectGetWidth(bounds);
	CGFloat height = CGRectGetHeight(bounds);
	return width >= 5.0 && width <= 40.0 && height >= 5.0 && height <= 20.0;
}

static void BMApplyCornerRadiusToLayerTree(CALayer *layer, CGFloat radius) {
	if (!layer) {
		return;
	}

	if (BMShouldRoundBatteryLayer(layer)) {
		layer.cornerRadius = MIN(radius, CGRectGetHeight(layer.bounds) * 0.5);
		layer.masksToBounds = radius > 0.0;
	}

	for (CALayer *sublayer in layer.sublayers) {
		BMApplyCornerRadiusToLayerTree(sublayer, radius);
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
	if (overlayBoltImageView && !visible) {
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
	UIColor *pinColor = BMPrefsShowsNub() ? bodyColor : UIColor.clearColor;

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
		[batteryView setPinColorAlpha:BMPrefsShowsNub() ? 1.0 : 0.0];
	}
	for (CALayer *sublayer in batteryView.layer.sublayers) {
		BMApplyCornerRadiusToLayerTree(sublayer, BMPrefsCornerRadius());
	}

	BMEnumerateSubviews(batteryView, ^(UIView *subview) {
		if ([subview isKindOfClass:[UILabel class]]) {
			UILabel *label = (UILabel *)subview;
			UILabel *overlayLabel = BMEnsureOverlayLabel(batteryView);
			UIImageView *overlayBoltImageView = BMEnsureOverlayBoltImageView(batteryView);
			if (label == overlayLabel) {
				return;
			}
			if (!objc_getAssociatedObject(label, BMLabelContainerFrameKey)) {
				objc_setAssociatedObject(label, BMLabelContainerFrameKey, [NSValue valueWithCGRect:label.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			}
			CGRect containerFrame = [objc_getAssociatedObject(label, BMLabelContainerFrameKey) CGRectValue];
			CGFloat overlayWidth = CGRectGetWidth(containerFrame) + BMOverlayExtraWidth();
			CGFloat overlayOriginX = CGRectGetMidX(containerFrame) - (overlayWidth * 0.5);
			CGFloat maxFontSize = label.font.pointSize + 7.0;
			UIColor *textColor = BMManagedBatteryViewTextColor(batteryView);
			BOOL useCutoutText = BMManagedBatteryViewUsesCutoutText(batteryView);
			NSString *displayText = BMManagedBatteryViewDisplayedText(batteryView, label);
			UIImageView *boltImageView = BMEnsureBoltImageView(batteryView);
			label.hidden = YES;
			label.alpha = 0.0;
			boltImageView.hidden = YES;
			if (displayText.length > 0) {
				if (BMManagedBatteryViewIsCharging()) {
					CGFloat boltReservedWidth = 7.5;
					CGFloat spacing = -1.0;
					CGFloat chargingWidthTrait = 0.0;
					UIFont *chargingFont = BMManagedBatteryViewInterpolatedFontToFitWidth(label.font, MAX(8.0, overlayWidth - boltReservedWidth - spacing), maxFontSize + 1.125, @"100", &chargingWidthTrait);
					BMConfigureOverlayLabel(overlayLabel, textColor, useCutoutText);
					overlayLabel.font = chargingFont;
					overlayLabel.attributedText = [[NSAttributedString alloc] initWithString:displayText attributes:@{
						NSForegroundColorAttributeName: textColor,
						NSFontAttributeName: chargingFont
					}];
					CGRect textRect = [displayText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40.0)
						options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
						attributes:@{ NSFontAttributeName: chargingFont }
						context:nil];
					UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:chargingFont.pointSize weight:UIImageSymbolWeightBold];
					UIImage *boltImage = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:configuration];
					boltImage = [boltImage imageWithTintColor:textColor renderingMode:UIImageRenderingModeAlwaysOriginal];
					CGFloat boltHeight = chargingFont.capHeight + 1.0;
					CGFloat boltWidth = boltImage ? (boltImage.size.width * (boltHeight / MAX(boltImage.size.height, 1.0))) : boltReservedWidth;
					CGFloat totalWidth = ceil(CGRectGetWidth(textRect)) + spacing + ceil(boltWidth);
					CGFloat groupStartX = floor(CGRectGetMidX(containerFrame) - (totalWidth * 0.5));
					CGFloat textHeight = ceil(CGRectGetHeight(textRect));
					CGFloat textY = CGRectGetMidY(containerFrame) - (textHeight * 0.5) - 0.5;
					overlayLabel.frame = CGRectMake(groupStartX, textY, ceil(CGRectGetWidth(textRect)) + 1.0, MAX(CGRectGetHeight(containerFrame), textHeight));
					overlayBoltImageView.image = boltImage;
					overlayBoltImageView.hidden = NO;
					overlayBoltImageView.frame = CGRectMake(CGRectGetMaxX(overlayLabel.frame) + spacing,
						CGRectGetMidY(overlayLabel.frame) - (boltHeight * 0.5) - 0.5,
						ceil(boltWidth),
						ceil(boltHeight));
					overlayBoltImageView.alpha = 1.0;
					overlayLabel.transform = CGAffineTransformIdentity;
					overlayBoltImageView.transform = CGAffineTransformIdentity;
					[batteryView bringSubviewToFront:overlayLabel];
					[batteryView bringSubviewToFront:overlayBoltImageView];
				} else {
					UIFont *normalFont = BMManagedBatteryViewFontToFitWidth(overlayWidth, maxFontSize, @"100");
					BMConfigureOverlayLabel(overlayLabel, textColor, useCutoutText);
					overlayLabel.font = normalFont;
					overlayLabel.frame = CGRectMake(overlayOriginX, CGRectGetMinY(containerFrame), overlayWidth, CGRectGetHeight(containerFrame));
					overlayLabel.attributedText = [[NSAttributedString alloc] initWithString:displayText attributes:@{
						NSForegroundColorAttributeName: textColor,
						NSFontAttributeName: normalFont
					}];
					overlayLabel.hidden = NO;
					overlayLabel.alpha = 1.0;
					overlayLabel.transform = CGAffineTransformIdentity;
					overlayBoltImageView.hidden = YES;
					overlayBoltImageView.transform = CGAffineTransformIdentity;
					[batteryView bringSubviewToFront:overlayLabel];
				}
			} else {
				overlayLabel.frame = containerFrame;
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
	BMLogBatteryMethodSurveyIfNeeded();
	if (!BMPrefsEnabled()) {
		BMShowStockLowPowerArtwork(controller);
		BMSetManagedBatteryVisibility(BMBatteryViewForController(controller), NO);
		return;
	}

	BMHideStockLowPowerArtwork(controller);

	_UIBatteryView *batteryView = BMEnsureBatteryView(controller);
	BOOL showsPercentage = BMBatteryPercentageEnabled();
	UIDevice *device = [UIDevice currentDevice];
	device.batteryMonitoringEnabled = YES;
	float batteryLevel = device.batteryLevel;
	NSInteger chargingState = (NSInteger)device.batteryState;
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
	BMWriteLogLine([NSString stringWithFormat:@"Refreshed low power tile controller=%@ batteryFrame=%@ pref=%@ level=%.3f charging=%ld active=%@ fill=%@ text=%@ body=%@ pin=%@",
		NSStringFromClass(controller.class),
		NSStringFromCGRect(batteryView.frame),
		showsPercentage ? @"on" : @"off",
		batteryLevel,
		(long)chargingState,
		active ? @"yes" : @"no",
		BMColorDescription([batteryView _batteryFillColor]),
		BMColorDescription([batteryView _batteryTextColor]),
		[batteryView respondsToSelector:@selector(bodyColor)] ? BMColorDescription([batteryView bodyColor]) : @"(n/a)",
		[batteryView respondsToSelector:@selector(pinColor)] ? BMColorDescription([batteryView pinColor]) : @"(n/a)"]);
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

		BMWriteLogLine([NSString stringWithFormat:@"Refreshing tracked controller=%@ reason=%@",
			NSStringFromClass(controller.class),
			reason ?: @"(unknown)"]);
		BMRefreshLowPowerLabel(controller);
	}
}

static void BMHandleControllerEvent(UIViewController *controller, NSString *eventName) {
	if (!BMIsLowPowerModuleController(controller) || !controller.isViewLoaded) {
		return;
	}

	BMTrackController(controller);
	BMWriteLogLine([NSString stringWithFormat:@"%@ %@ bounds=%@",
		NSStringFromClass(controller.class),
		eventName,
		NSStringFromCGRect(controller.view.bounds)]);
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

static void BMPrefsDidChangeCallback(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
	BMRefreshTrackedControllers(@"prefsChanged");
}

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
		[@"" writeToFile:BMLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[UIDevice currentDevice].batteryMonitoringEnabled = YES;
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
			NULL,
			BMPrefsDidChangeCallback,
			BMPrefsReloadNotification,
			NULL,
			CFNotificationSuspensionBehaviorDeliverImmediately);
		__unused static BMBatteryMirrorObserver *observer = nil;
		observer = [[BMBatteryMirrorObserver alloc] init];
		BMWriteLogLine(@"BatteryMirror loaded");
	}
}
