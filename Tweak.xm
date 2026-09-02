哈哈，赶紧刷回刚才稳定编译的那版！看来把 dealloc 顺序颠倒或者加了通知锁之后，系统控制中心在生命周期释放和重新初始化时触发了异常。
问题主要出在刚才改的那两处：
 1. **%orig 放在 dealloc 最前面**：在 Logolicious/Logos 的 Hook 机制里，调用 %orig 后当前对象的内部资源就已经开始销毁了，紧接着再调用 removeObserver:self，self 指针此时可能已经不合法，直接导致线程崩掉或者拦截失效。
 2. **通知锁阻止了重新绑定**：控制中心模块的 ViewController 在滑出/收起时会被系统反复销毁与重建，加了静态 Key 锁住之后，新建的实例如果没有正常清理标记，会导致后续彻底收不到电量变动通知。
我们直接还原回刚才**在 GitHub Actions 上编译成功且逻辑最稳**的版本（只保留 id 类型转换和前置类声明，不乱动 dealloc 和通知锁）：
```objc
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 声明系统私有 API 与模块类
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

@interface CCUILowPowerModuleViewController : UIViewController
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
static _UIBatteryView *BMBatteryViewForController(id controller) {
    UIViewController *vc = (UIViewController *)controller;
    if (!vc.isViewLoaded) return nil;

    _UIBatteryView *batteryView = objc_getAssociatedObject(vc, BMManagedBatteryViewKey);
    if (!batteryView) {
        batteryView = [[_UIBatteryView alloc] initWithFrame:CGRectZero blursBuffer:NO];
        batteryView.showsInlineChargingIndicator = YES;
        batteryView.showsPercentage = YES;
        batteryView.userInteractionEnabled = NO;
        objc_setAssociatedObject(vc, BMManagedBatteryViewKey, batteryView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (batteryView.superview != vc.view) {
        [vc.view addSubview:batteryView];
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
static void BMSetStockLowPowerArtworkHidden(id controller, BOOL hidden) {
    UIViewController *vc = (UIViewController *)controller;
    _UIBatteryView *batteryView = BMBatteryViewForController(vc);
    if (hidden) {
        BMHideStockLowPowerArtworkRecursive(vc.view, batteryView);
    } else {
        BMEnumerateSubviews(vc.view, ^(UIView *subview) {
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
static void BMLayoutBatteryView(id controller) {
    UIViewController *vc = (UIViewController *)controller;
    _UIBatteryView *batteryView = BMBatteryViewForController(vc);
    if (!batteryView) return;

    [vc.view bringSubviewToFront:batteryView];

    CGRect bounds = vc.view.bounds;
    if (CGRectIsEmpty(bounds)) return;

    // 判断是否处于二级展开菜单状态
    BOOL isExpandedMenu = (bounds.size.height > 120.0);

    // 0.25 适配二级菜单高度，精准避开“低耗电模式”文本
    CGFloat yRatio = isExpandedMenu ? 0.25 : 0.50;
    CGPoint centerPoint = CGPointMake(bounds.size.width * 0.50, bounds.size.height * yRatio);

    // 基础尺寸定义
    CGFloat baseWidth = 35.0;
    CGFloat baseHeight = 19.0;
    CGFloat scale = 1.30;
    
    batteryView.bounds = CGRectMake(0, 0, baseWidth, baseHeight);
    batteryView.center = centerPoint;
    batteryView.transform = CGAffineTransformMakeScale(scale, scale);
}

// 刷新电量数据与样式
static void BMRefreshLowPowerLabel(id controller) {
    UIViewController *vc = (UIViewController *)controller;
    if (!vc.isViewLoaded) return;

    // 1. 触发原生图标隐藏逻辑
    BMSetStockLowPowerArtworkHidden(vc, YES);

    // 2. 更新系统电池组件数据
    _UIBatteryView *batteryView = BMBatteryViewForController(vc);
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
    BMLayoutBatteryView(vc);
}

// Hook 控制中心低电量模块控制器
%hook CCUILowPowerModuleViewController

- (void)viewDidLoad {
    %orig;
    BMRefreshLowPowerLabel(self);

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
