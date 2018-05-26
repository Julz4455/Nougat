#import "NUANotificationShadePageContainerViewController.h"

@implementation NUANotificationShadePageContainerViewController

#pragma mark - Initialization

- (instancetype)initWithContentViewController:(UIViewController<NUANotificationShadePageContentProvider> *)viewController {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _contentViewController = viewController;
    }

    return self;
}

#pragma mark - View management

- (void)loadView {
    NUANotificationShadePanelView *panelView = [[NUANotificationShadePanelView alloc] initWithDefaultSize];
    self.view = panelView;
}

- (void)viewDidLoad {
    [self addChildViewController:self.contentViewController];
    [self _panelView].contentView = self.contentViewController.view;
    [self.contentViewController didMoveToParentViewController:self];


    [super viewDidLoad];
}

- (NUANotificationShadePanelView *)_panelView {
    return (NUANotificationShadePanelView *)self.view;
}

#pragma mark - Delegate

- (CGFloat)presentedHeight {
    return self.contentViewController.presentedHeight;
}

- (void)setPresentedHeight:(CGFloat)height {
    // Pass on to content vc
    self.contentViewController.presentedHeight = height;
}

@end