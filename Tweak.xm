#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 声明系统私有 API 与结构体
@interface _UIBatteryView : UIView
@property (nonatomic, assign) NSInteger chargingState;
@property (nonatomic, assign) CGFloat chargePercent;
@property (nonatomic, assign) BOOL saverModeActive;
@property (nonatomic, assign) BOOL showsInlineChargingIndicator;
@property (nonatomic, assign) BOOL showsPercentage;
@property (nonatomic, strong) UIColor *bodyColor;
@property (nonatomic, strong) UIColor *pinColor;
@property (nonatomic, strong) UIColor *boltColor;
@property (nonatomic, strong) UIColor *fillColor;
- (instancetype)initWithFrame:(CGRect)frame blursBuffer:(BOOL)blursBuffer;
@end

// Associated Object 静态指针 Key
static void *const BMManagedBatteryViewKey = (void *)&BMManagedBatteryViewKey;
static void *const BMHiddenStockArtworkTagKey = (void *)&BMHiddenStockArtworkTagKey;

// 辅助函数：深度递归遍历子视图
static void BMEnumerateSubviews(UIView *view, void (^block)(UIView *subview)) {
    if (!view) return;
    block(view);
    for (UIView *subview in view.subviews) {
        BMEnumerateSubviews(subview, block);
    }
}

// 获取或创建咱们自定义的电池视图
static _UIBatteryView *BMBatteryViewForController(UIViewController *controller) {
    if (!controller.isViewLoaded) return nil;
    _UIBatteryView *batteryView = objc_getAssociatedObject(controller, BMManagedBatteryViewKey);
    if (!batteryView) {
        batteryView = [[_UIBatteryView alloc] initWithFrame:CGRectZero blursBuffer:NO];
        batteryView.showsInlineChargingIndicator = YES;
        batteryView.showsPercentage = YES;
        batteryView.userInteractionEnabled = NO;
        objc_setAssociatedObject(controller, BMManagedBatteryViewKey, batteryView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (batteryView.superview != controller.view) {
        [controller.view addSubview:batteryView];
    }
    return batteryView;
}

// 递归隐藏原生低电量图标（基于视图实例打标记）
static void BMHideStockLowPowerArtworkRecursive(UIView *view, _UIBatteryView *ourBatteryView) {
    if (!view) return;

    // 跳过咱们自己生成的电池视图及其子视图
    if (ourBatteryView && (view == ourBatteryView || [view isDescendantOfView:ourBatteryView])) {
        return;
    }

    // 已处理过的视图直接跳过，避免重复设置属性
    NSNumber *tag = objc_getAssociatedObject(view, BMHiddenStockArtworkTagKey);
    if ([tag boolValue]) {
        return;
    }

    NSString *clsName = NSStringFromClass(view.class);
    if ([view isKindOfClass:[UIImageView class]] || [clsName containsString:@"CCUICAPackageView"]) {
        view.hidden = YES;
        view.alpha = 0.0;
        objc_setAssociatedObject(view, BMHiddenStockArtworkTagKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    for (UIView *subview in view.subviews) {
        BMHideStockLowPowerArtworkRecursive(subview, ourBatteryView);
    }
}

// 统一对外控制隐藏/恢复的入口
static void BMSetStockLowPowerArtworkHidden(UIViewController *controller, BOOL hidden) {
    _UIBatteryView *batteryView = BMBatteryViewForController(controller);
    if (hidden) {
        BMHideStockLowPowerArtworkRecursive(controller.view, batteryView);
    } else {
        BMEnumerateSubviews(controller.view, ^(UIView *subview) {
            NSNumber *tag = objc_getAssociatedObject(subview, BMHiddenStockArtworkTagKey);
            if ([tag boolValue]) {
                subview.hidden = NO;
                subview.alpha = 1.0;
                objc_setAssociatedObject(subview, BMHiddenStockArtworkTagKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        });
    }
}

// 重新布局电池视图（适配一级模块与二级展开菜单）
static void BMLayoutBatteryView(UIViewController *controller) {
    _UIBatteryView *batteryView = BMBatteryViewForController(controller);
    if (!batteryView) return;

    [controller.view bringSubviewToFront:batteryView];

    CGRect bounds = controller.view.bounds;
    if (CGRectIsEmpty(bounds)) return;

    // 判断是否处于二级展开菜单状态
    BOOL isExpandedMenu = (bounds.size.height > 120.0);

    // 0.25 适配二级菜单高度，避免遮挡“低耗电模式”文字
    CGFloat yRatio = isExpandedMenu ? 0.25 : 0.50;
    CGPoint centerPoint = CGPointMake(bounds.size.width * 0.50, bounds.size.height * yRatio);

    // 基础尺寸定义
    CGFloat baseWidth = 35.0;
    CGFloat baseHeight = 19.0;
    
    // 保持 1.30 倍适度放大
    CGFloat scale = 1.30;
    
    batteryView.bounds = CGRectMake(0, 0, baseWidth, baseHeight);
    batteryView.center = centerPoint;
    batteryView.transform = CGAffineTransformMakeScale(scale, scale);
}

// 刷新电量数据与样式
static void BMRefreshLowPowerLabel(UIViewController *controller) {
    if (!controller.isViewLoaded) return;

    // 1. 触发原生图标隐藏逻辑
    BMSetStockLowPowerArtworkHidden(controller, YES);

    // 2. 更新系统电池组件数据
    _UIBatteryView *batteryView = BMBatteryViewForController(controller);
    if (!batteryView) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    NSInteger state = isLowPower ? 1 : 0;

    batteryView.chargePercent = level;
    batteryView.chargingState = state;
    batteryView.saverModeActive = isLowPower;

    // 动态调色
    UIColor *contentColor = isLowPower ? [UIColor systemYellowColor] : [UIColor whiteColor];
    batteryView.bodyColor = [contentColor colorWithAlphaComponent:0.4];
    batteryView.pinColor = [contentColor colorWithAlphaComponent:0.4];
    batteryView.fillColor = contentColor;
    batteryView.boltColor = [UIColor blackColor];

    // 3. 重新绘制布局
    BMLayoutBatteryView(controller);
}

// Hook 控制中心低电量模块控制器
%hook CCUILowPowerModuleViewController

- (void)viewDidLoad {
    %orig;
    BMRefreshLowPowerLabel(self);

    // 监听电量与低电量模式变化通知
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(bm_updateBatteryState) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(bm_updateBatteryState) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
}

- (void)viewWillLayoutSubviews {
    %orig;
    BMLayoutBatteryView(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BMRefreshLowPowerLabel(self);
}

%new
- (void)bm_updateBatteryState {
    dispatch_async(dispatch_get_main_queue(), ^{
        BMRefreshLowPowerLabel(self);
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%end
