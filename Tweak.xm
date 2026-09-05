#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// -----------------------------------------------------------------------------
// 1. 全机型物理等比例 Scale 自适应算法（基于 14 Pro 852pt -> 1.40 黄金基准）
// -----------------------------------------------------------------------------
static CGFloat BMGetAdaptiveScale(void) {
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    // 以 14 Pro (852pt) 的 1.40 缩放为基准进行线性映射
    CGFloat scale = screenHeight * (1.40 / 852.0);
    
    // 设定安全边界：防止小屏（如 SE）撑爆或大屏（如 16PM）过大
    if (scale < 1.15) scale = 1.15;
    if (scale > 1.55) scale = 1.55;
    
    return scale;
}

// -----------------------------------------------------------------------------
// 2. 动态字号自适应算法（试算宽度上限，装不下自动递减，最高 11.1pt）
// -----------------------------------------------------------------------------
static UIFont *BMManagedBatteryViewFontToFitWidth(CGFloat targetWidth, CGFloat maxFontSize, NSString *referenceText) {
    if (targetWidth <= 0.0) {
        return [UIFont boldSystemFontOfSize:maxFontSize];
    }

    NSString *sampleText = (referenceText.length > 0) ? referenceText : @"100";
    CGFloat minFontSize = 7.0;
    UIFont *bestFont = [UIFont boldSystemFontOfSize:maxFontSize];

    for (CGFloat fontSize = maxFontSize; fontSize >= minFontSize; fontSize -= 0.5) {
        UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
        CGRect textRect = [sampleText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                                   options:NSStringDrawingUsesLineFragmentOrigin
                                                attributes:@{NSFontAttributeName : font}
                                                   context:nil];
        bestFont = font;
        if (ceil(CGRectGetWidth(textRect)) <= targetWidth) {
            break;
        }
    }

    return bestFont;
}

// -----------------------------------------------------------------------------
// 3. 核心文本渲染与像素级绝对居中
// -----------------------------------------------------------------------------
static void BMApplyBatteryStyling(_UIBatteryView *batteryView) {
    if (!batteryView) return;

    UILabel *overlayLabel = nil;
    UILabel *nativeLabel = nil;

    for (UIView *subview in batteryView.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label respondsToSelector:@selector(accessibilityIdentifier)] &&
                [label.accessibilityIdentifier isEqualToString:@"BMBatteryOverlayLabel"]) {
                overlayLabel = label;
            } else {
                nativeLabel = label;
            }
        }
    }

    if (!overlayLabel) {
        overlayLabel = [[UILabel alloc] init];
        overlayLabel.accessibilityIdentifier = @"BMBatteryOverlayLabel";
        overlayLabel.textAlignment = NSTextAlignmentCenter;
        overlayLabel.adjustsFontSizeToFitWidth = NO;
        overlayLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
        [batteryView addSubview:overlayLabel];
    }

    // 隐藏原生数字 Label，由自定义 Overlay 完美接管
    if (nativeLabel) {
        nativeLabel.hidden = YES;
        nativeLabel.alpha = 0.0;
    }

    // 获取电池百分比
    NSInteger percent = (NSInteger)round(batteryView.chargePercent * 100.0);
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    NSString *displayText = [NSString stringWithFormat:@"%ld", (long)percent];

    // 获取原生尺寸基准
    CGFloat parentWidth = CGRectGetWidth(batteryView.bounds);
    CGFloat parentHeight = CGRectGetHeight(batteryView.bounds);
    
    // 扣除电池右侧小极柱后的内部可绘制宽度
    CGFloat overlayWidth = floor(parentWidth * 0.78);
    CGFloat maxFontSize = 11.1;

    // 动态计算该电量下的最适字号
    UIFont *font = BMManagedBatteryViewFontToFitWidth(overlayWidth, maxFontSize, displayText);

    // 设置文本与状态颜色
    overlayLabel.font = font;
    overlayLabel.text = displayText;
    overlayLabel.textColor = (batteryView.saverModeActive || batteryView.charging) ? [UIColor blackColor] : [UIColor whiteColor];

    // 精确计算文字尺寸并进行像素对齐（像素级居中）
    CGSize textSize = [displayText sizeWithAttributes:@{NSFontAttributeName : font}];
    CGFloat labelWidth = ceil(textSize.width);
    CGFloat labelHeight = ceil(textSize.height);

    CGFloat centerX = floor((overlayWidth - labelWidth) * 0.5) + 0.5;
    CGFloat centerY = floor((parentHeight - labelHeight) * 0.5) + 0.5;

    // 重置文字 Transform 保持矢量清晰，锁定 Frame
    overlayLabel.transform = CGAffineTransformIdentity;
    overlayLabel.frame = CGRectMake(centerX, centerY, labelWidth, labelHeight);
    [batteryView bringSubviewToFront:overlayLabel];
}

// -----------------------------------------------------------------------------
// 4. 控制中心模块入口布局逻辑
// -----------------------------------------------------------------------------
static void BMLayoutBatteryView(UIViewController *controller) {
    _UIBatteryView *batteryView = nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"_UIBatteryView")]) {
            batteryView = (_UIBatteryView *)subview;
            break;
        }
    }

    if (!batteryView || !batteryView.superview) return;

    CGRect bounds = controller.view.bounds;
    CGFloat viewHeight = CGRectGetHeight(bounds);
    CGFloat width = MIN(CGRectGetWidth(bounds) - 8.0, 31.0);
    CGFloat height = 16.0;
    CGFloat x = floor((CGRectGetWidth(bounds) - width) * 0.5);

    BOOL isExpandedMenu = viewHeight > 120.0;
    CGFloat yRatio = isExpandedMenu ? 0.25 : 0.50;
    CGFloat y = floor(viewHeight * yRatio - height * 0.5);

    // 1. 设置原始几何 Frame
    batteryView.frame = CGRectMake(x, y, width, height);

    // 2. 应用文字自适应与样式渲染
    BMApplyBatteryStyling(batteryView);

    // 3. 应用基于硬件屏幕高度的动态比例缩放
    CGFloat scale = BMGetAdaptiveScale();
    batteryView.transform = CGAffineTransformMakeScale(scale, scale);
    
    [controller.view bringSubviewToFront:batteryView];
}
