#import "NUAMainTableViewController.h"
#import "NUAMediaTableViewCell.h"
#import "NUARippleButton.h"
#import <MediaRemote/MediaRemote.h>
#import <SpringBoard/SpringBoard-Umbrella.h>
#import <Macros.h>
#import <UIKitHelpers.h>

@interface NUAMainTableViewController () {
    NSMutableArray<NUACoalescedNotification *> *_expandedNotifications;
    NSLayoutConstraint *_heightConstraint;
    NUACoalescedNotification *_mediaNotification;
}

@property (strong, nonatomic) NUARippleButton *clearAllButton;

@end

@implementation NUAMainTableViewController

#pragma mark - Initialization

- (instancetype)initWithPreferences:(NUAPreferenceManager *)notificationShadePreferences {
    self = [super init];
    if (self) {
        // Set defaults
        _notificationShadePreferences = notificationShadePreferences;
        _expandedNotifications = [NSMutableArray array];
        _mediaNotification = [NUACoalescedNotification mediaNotification];

        // Determine unlock defaults
        switch (notificationShadePreferences.notificationPreviewSetting) {
            case NUANotificationPreviewSettingAlways:
                _UILocked = NO;
                break;
            case NUANotificationPreviewSettingWhenUnlocked:
                _UILocked = [[NSClassFromString(@"SBLockScreenManager") sharedInstance] isUILocked];
                break;
            case NUANotificationPreviewSettingNever:
                _UILocked = YES;
                break;
        }

        // Create tableview controller
        _tableViewController = [[UITableViewController alloc] initWithStyle:UITableViewStylePlain];
        [self addChildViewController:_tableViewController];

        // Create now playing controller
        _nowPlayingController = [[NSClassFromString(@"MPUNowPlayingController") alloc] init];

        // Notifications
        _notificationRepository = [NUANotificationRepository defaultRepository];
        [_notificationRepository addObserver:self];

        // Register for notifications
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(_handleBacklightFadeFinished:) name:@"SBBacklightFadeFinishedNotification" object:nil];
        [center addObserver:self selector:@selector(_handleUIDidLock:) name:@"SBLockScreenUIDidLockNotification" object:nil];
        [center addObserver:self selector:@selector(_handleBiometricAuthenticated:) name:@"SBBiometricEventMonitorHasAuthenticated" object:nil];
        [center addObserver:self selector:@selector(preferencesDidChange:) name:@"NUANotificationShadeChangedPreferences" object:nil];
    }

    return self;
}

- (void)_loadNotificationsIfNecessary {
    if (self.notifications) {
        // Generate only once
        return;
    }

    // Add all entries from repository
    NSDictionary<NSString *, NSDictionary<NSString *, NUACoalescedNotification *> *> *allNotifications = self.notificationRepository.notifications;
    NSMutableArray<NUACoalescedNotification *> *notifications = [NSMutableArray array];
    for (NSDictionary<NSString *, NUACoalescedNotification *> *notificationGroups in allNotifications.allValues) {
        // Add all entries from each array
        NSArray<NUACoalescedNotification *> *notificationThreads = notificationGroups.allValues;
        [notifications addObjectsFromArray:notificationThreads];
    }

    // Sort via date
    [notifications sortUsingComparator:^(NUACoalescedNotification *notification1, NUACoalescedNotification *notification2) {
        return [notification1 compare:notification2];
    }];

    // Set notifications
    _notifications = [notifications copy];

    // Reload data
    [self.tableViewController.tableView reloadData];
}

#pragma mark - Properties

- (void)setUILocked:(BOOL)UILocked {
    if (_UILocked == UILocked || self.notificationShadePreferences.notificationPreviewSetting != NUANotificationPreviewSettingWhenUnlocked) {
        // Nothing to change, or never change
        return;
    }

    _UILocked = UILocked;

    // Reload cells
    [self.tableViewController.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (CGFloat)contentHeight {
    return self.tableViewController.tableView.contentSize.height;
}

- (void)setPresentedHeight:(CGFloat)height {
    _presentedHeight = height;
    if (height < 150.0) {
        // Since cant really return here, ensure proper height set
        height = 150.0;
    }

    _heightConstraint.constant = height - 95.0;
}

- (void)setRevealPercentage:(CGFloat)revealPercentage {
    _revealPercentage = revealPercentage;

    // Adjust whether table should start cutting off
    CGFloat fullPanelHeight = [self.delegate tableViewControllerRequestsPanelContentHeight:self];
    CGFloat safeAreaHeight = [self _bottomSafeArea];
    if ((self.contentHeight + fullPanelHeight) <= safeAreaHeight) {
        // No need to ever cutoff
        return;
    }

    // Calculate cutoff
    CGFloat originalPresentedHeight = MIN(safeAreaHeight, self.contentHeight + 150.0);
    CGFloat addedHeight = ((fullPanelHeight - 150.0) * revealPercentage);
    CGFloat totalHeight = originalPresentedHeight + addedHeight;
    CGFloat heightToRemove = totalHeight - safeAreaHeight;
    CGFloat newPresentedHeight = originalPresentedHeight - heightToRemove;
    if (newPresentedHeight > originalPresentedHeight) {
        newPresentedHeight = originalPresentedHeight;
    }

    self.presentedHeight = newPresentedHeight;
}

#pragma mark - Screen Bounds Helpers

- (CGFloat)_bottomSafeArea {
    UIInterfaceOrientation currentOrientation = [(SpringBoard *)[UIApplication sharedApplication] activeInterfaceOrientation];
    CGFloat currentScreenHeight = NUAGetScreenHeightForOrientation(currentOrientation);
    return currentScreenHeight - 100.0;
}

- (BOOL)containsPoint:(CGPoint)point {
    // Check our view
    CGPoint convertedPoint = [self.view convertPoint:point fromView:self.view.superview];
    BOOL insideTableView = CGRectContainsPoint(self.tableViewController.tableView.bounds, convertedPoint);

    // Check the button
    CGRect clearButtonFrame = self.clearAllButton.frame;
    BOOL insideButton = CGRectContainsPoint(clearButtonFrame, convertedPoint);
    return insideTableView || insideButton;
}

#pragma mark - Observer

- (void)notificationRepositoryAddedNotification:(NUACoalescedNotification *)newNotification {
    if (!self.notifications) {
        // Notification shade hasnt been loaded
        return;
    }

    // Add new entry
    NSMutableArray<NUACoalescedNotification *> *notifications = [self.notifications mutableCopy];
    NSUInteger insertIndex = [self _indexForAddingNewNotification:newNotification];
    if (insertIndex >= notifications.count) {
        // Simply add to end
        insertIndex = notifications.count;
        [notifications addObject:newNotification];
    } else {
        [notifications insertObject:newNotification atIndex:insertIndex];
    }
    
    // Update ivar
    _notifications = [notifications copy];

    // Update table
    [self.tableViewController.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:insertIndex inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];

    // Update height
    [self _resizeTableForExpansion:YES forNotification:YES];
}

- (void)notificationRepositoryUpdatedNotification:(NUACoalescedNotification *)updatedNotification {
    if (!self.notifications) {
        // Notification shade hasnt been loaded
        return;
    }

    // Get old index
    NSIndexPath *oldIndexPath = [self indexPathForNotification:updatedNotification];

    // Sort via date
    // Since references, the notification in the array is already updated, all thats needed is to sort
    NSMutableArray<NUACoalescedNotification *> *notifications = [self.notifications mutableCopy];
    [notifications sortUsingComparator:^(NUACoalescedNotification *notification1, NUACoalescedNotification *notification2) {
        return [notification1 compare:notification2];
    }];

    _notifications = [notifications copy];

    // Get new index
    NSIndexPath *newIndexPath = [self indexPathForNotification:updatedNotification];

    // Update table
    if (newIndexPath.row == oldIndexPath.row) {
        // Simply just reload the cell, no need to insert and delete
        [self.tableViewController.tableView reloadRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        // Just call move
        [self.tableViewController.tableView moveRowAtIndexPath:oldIndexPath toIndexPath:newIndexPath];
    }
}

- (void)notificationRepositoryRemovedNotification:(NUACoalescedNotification *)removedNotification {
    if (!self.notifications) {
        // Notification shade hasnt been loaded
        return;
    }

    // Update expansion status
    // Due to reference stuff, updatedNotification and oldNotification are the same
    [self notification:removedNotification shouldExpand:NO reload:NO];

    // Remove old and update
    NSIndexPath *oldIndexPath = [self indexPathForNotification:removedNotification];

    NSMutableArray<NUACoalescedNotification *> *notifications = [self.notifications mutableCopy];
    [notifications removeObject:removedNotification];
    _notifications = [notifications copy];

    // Update table
    [self.tableViewController.tableView deleteRowsAtIndexPaths:@[oldIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];

    // Update presented height
    [self _resizeTableForExpansion:NO forNotification:YES];
}

- (void)_resizeTableForExpansion:(BOOL)expand forNotification:(BOOL)forNotification {
    // Calculate current heights
    CGFloat proposedHeightToAdd = forNotification ? (expand ? 100.0 : -100.0) : (expand ? 50.0 : -50.0);
    CGFloat fullPanelHeight = [self.delegate tableViewControllerRequestsPanelContentHeight:self];
    CGFloat currentPanelHeight = ((fullPanelHeight - 150.0) * self.revealPercentage) + 150.0;
    CGFloat currentContentHeight = currentPanelHeight + self.contentHeight;
    CGFloat proposedNewHeight = currentContentHeight + proposedHeightToAdd;

    // Check if can expand/collapse
    CGFloat safeAreaHeight = [self _bottomSafeArea];
    BOOL canExpand = currentContentHeight < safeAreaHeight;
    BOOL canCollapse = proposedNewHeight < safeAreaHeight;
    BOOL canResize = expand ? canExpand : canCollapse;
    if (!canResize) {
        // Any changes would be beyond safe area, return
        return;
    }

    // Calculate how much to add/subtract
    CGFloat expandableHeight = expand ? (safeAreaHeight - currentContentHeight) : (safeAreaHeight - proposedNewHeight);
    CGFloat actualHeightToAdd = MIN(fabs(proposedHeightToAdd), expandableHeight);
    actualHeightToAdd *= expand ? 1.0 : -1.0;

    // Animate
    [UIView animateWithDuration:0.4 animations:^{
        self.presentedHeight += actualHeightToAdd;
    }];
}

- (NSUInteger)_indexForAddingNewNotification:(NUACoalescedNotification *)notification {
    // Compare notifications
    return [self.notifications indexOfObject:notification inSortedRange:NSMakeRange(0, self.notifications.count) options:(NSBinarySearchingFirstEqual | NSBinarySearchingInsertionIndex) usingComparator:^(NUACoalescedNotification *notification1, NUACoalescedNotification *notification2) {
        return [notification1 compare:notification2];
    }];
}

- (NUACoalescedNotification *)notificationForIndexPath:(NSIndexPath *)indexPath {
    return self.notifications[indexPath.row];
}

- (NSIndexPath *)indexPathForNotification:(NUACoalescedNotification *)notification {
    // Get index from array and return
    NSUInteger index = [self.notifications indexOfObject:notification];
    return [NSIndexPath indexPathForRow:index inSection:0];
}

#pragma mark - Notification Launching

- (void)executeNotificationAction:(NSString *)type forCellAtIndexPath:(NSIndexPath *)indexPath {
    // Get associated entry
    NUACoalescedNotification *notification = [self notificationForIndexPath:indexPath];
    if (!notification || [notification isEqual:_mediaNotification]) {
        // Invalid notification
        return;
    }

    // Determine action
    NUANotificationEntry *entry = notification.leadingNotificationEntry;
    NCNotificationRequest *request = entry.request;
    NCNotificationAction *action = nil;
    if ([type isEqualToString:@"default"]) {
        action = request.defaultAction;
    } else if ([type isEqualToString:@"clear"]) {
        action = request.clearAction;
    }

    if (!action) {
        return;
    }

    // Call the repository
    [self.notificationRepository executeAction:action forNotificationRequest:request];

    if (![type isEqualToString:@"default"]) {
        return;
    }

    // Dismiss if needed
    [self.delegate tableViewControllerWantsDismissal:self];
}

#pragma mark - UIViewController

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    _heightConstraint = [view.heightAnchor constraintEqualToConstant:55.0];
    _heightConstraint.active = YES;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Configure tableView
    self.tableViewController.tableView.dataSource = self;
    self.tableViewController.tableView.delegate = self;
    self.tableViewController.tableView.estimatedRowHeight = 100.0;
    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableViewController.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.tableViewController.tableView];

    self.tableViewController.tableView.layoutMargins = UIEdgeInsetsZero;
    self.tableViewController.tableView.separatorInset = UIEdgeInsetsZero;

    // // constraint up
    [self.tableViewController.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.tableViewController.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-55.0].active = YES;
    [self.tableViewController.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.tableViewController.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;

    // Register custom classes
    [self.tableViewController.tableView registerClass:[NUANotificationTableViewCell class] forCellReuseIdentifier:@"NotificationCell"];
    [self.tableViewController.tableView registerClass:[NUAMediaTableViewCell class] forCellReuseIdentifier:@"MediaCell"];

    // Add clear all button
    _clearAllButton = [[NUARippleButton alloc] init];
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *localizedClearAll = [bundle localizedStringForKey:@"CLEAR_ALL" value:@"Clear All" table:@"Localizable"];
    [self.clearAllButton setTitle:localizedClearAll forState:UIControlStateNormal];
    [self.clearAllButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.clearAllButton addTarget:self action:@selector(_handleClearButtonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    self.clearAllButton.rippleStyle = NUARippleStyleUnbounded;
    self.clearAllButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.clearAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.clearAllButton];

    // Button constraints
    [self.clearAllButton.topAnchor constraintEqualToAnchor:self.tableViewController.tableView.bottomAnchor].active = YES;
    [self.clearAllButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-5.0].active = YES;
    [self.clearAllButton.heightAnchor constraintEqualToConstant:55.0].active = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Populate notifications
    [self _loadNotificationsIfNecessary];

    // Notifications
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_updateMedia) name:(__bridge_transfer NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification object:nil];

    // Update media if needed
    [self _updateMedia];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    // Stop listening for Notifs
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:(__bridge_transfer NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification object:nil];

    // Remove media cell if needed
    [self removeMediaCellIfNecessary];
}

- (BOOL)_canShowWhileLocked {
    // New on iOS 13
    return YES;
}

#pragma mark - Notifications

- (void)_updateMedia {
    // Make sure on the main thread since the notification is dispatched on a mediaremote thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self insertMediaCellIfNeccessary];
    });
}

- (void)_handleBacklightFadeFinished:(NSNotification *)notification {
    // Dismiss if screen is turned off
    BOOL screenIsOn = ((SBBacklightController *)[NSClassFromString(@"SBBacklightController") sharedInstance]).screenIsOn;

    if (!screenIsOn) {
        self.UILocked = YES;
    }
}

- (void)_handleUIDidLock:(NSNotification *)notification {
    // Dismiss if screen is turned off
    BOOL screenIsOn = ((SBBacklightController *)[NSClassFromString(@"SBBacklightController") sharedInstance]).screenIsOn;

    if (screenIsOn) {
        self.UILocked = YES;
    }
}

- (void)_handleBiometricAuthenticated:(NSNotification *)notification {
    // Authenticated, show
    self.UILocked = NO;
}

- (void)preferencesDidChange:(NSNotification *)notification {
    // Change UILock settings
    switch (self.notificationShadePreferences.notificationPreviewSetting) {
        case NUANotificationPreviewSettingAlways:
            _UILocked = NO;
            break;
        case NUANotificationPreviewSettingWhenUnlocked:
            _UILocked = [[NSClassFromString(@"SBLockScreenManager") sharedInstance] isUILocked];
            break;
        case NUANotificationPreviewSettingNever:
            _UILocked = YES;
            break;
    }

    // Update table
    [self.tableViewController.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Media

- (BOOL)_mediaCellPresent {
    if (!self.notifications || self.notifications.count < 1) {
        // Cant check something that doesnt exist
        return NO;
    }

    // Check if first notification is media
    NUACoalescedNotification *topNotification = self.notifications.firstObject;
    return topNotification.type == NUANotificationTypeMedia;
}

- (void)insertMediaCellIfNeccessary {
    if ([self _mediaCellPresent] || !self.nowPlayingController.isPlaying || !self.notifications) {
        // cant add if already exists, or not playing, or if nothing to add to
        return;
    }

    // Add dummie to backng array
    NSMutableArray<NUACoalescedNotification *> *mutableNotifications = [self.notifications mutableCopy];
    [mutableNotifications insertObject:_mediaNotification atIndex:0];
    _notifications = [mutableNotifications copy];

    // Insert row
    [self.tableViewController.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];

    // Update presented height
    [self _resizeTableForExpansion:YES forNotification:YES];
}

- (void)removeMediaCellIfNecessary {
    if (![self _mediaCellPresent] || self.nowPlayingController.isPlaying) {
        // Cant remove something i dont have or cant remove something i need
        return;
    }

    // Update expansion status
    [self notification:_mediaNotification shouldExpand:NO reload:NO];

    // Remove media cell
    NSMutableArray<NUACoalescedNotification *> *mutableNotifications = [self.notifications mutableCopy];
    [mutableNotifications removeObject:_mediaNotification];
    _notifications = [mutableNotifications copy];

    // Delete row
    [self.tableViewController.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
    
    // Update presented height
    [self _resizeTableForExpansion:NO forNotification:YES];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:[NUAMediaTableViewCell class]]) {
        // Not media cell
        return;
    }

    // Register media cell notifications
    NUAMediaTableViewCell *mediaCell = (NUAMediaTableViewCell *)cell;
    [mediaCell registerForMediaNotifications];
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:[NUAMediaTableViewCell class]]) {
        // Not media cell
        return;
    }

    // Unregister media cell notifications
    NUAMediaTableViewCell *mediaCell = (NUAMediaTableViewCell *)cell;
    [mediaCell unregisterForMediaNotifications];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0 && [self _mediaCellPresent]) {
        NSString *nowPlayingID = self.nowPlayingController.nowPlayingAppDisplayID;
        if (!nowPlayingID) {
            // No now playing app
            return;
        }

        // Launch music playing app
        [(SpringBoard *)[UIApplication sharedApplication] launchApplicationWithIdentifier:nowPlayingID suspended:NO];

        // Dismiss nougat
        [self.delegate tableViewControllerWantsDismissal:self];
    } else {
        // Launch notif
        [self executeNotificationAction:@"default" forCellAtIndexPath:indexPath];
    }
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Add our swipe action
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *localizedClear = [bundle localizedStringForKey:@"CLEAR" value:@"Clear" table:@"Localizable"];
    __weak __typeof(self) weakSelf = self;
    UITableViewRowAction *clearAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:localizedClear handler:^(UITableViewRowAction *action, NSIndexPath *indexPath) {
        [weakSelf executeNotificationAction:@"clear" forCellAtIndexPath:indexPath];
    }];

    UIColor *actionColor = self.notificationShadePreferences.usingDark ? [UIColor colorWithRed: 0.93 green: 0.93 blue: 0.93 alpha: 1.00] : [UIColor colorWithRed: 0.07 green: 0.07 blue: 0.07 alpha: 1.00];
    clearAction.backgroundColor = actionColor;

    return @[clearAction];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.notifications.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NUACoalescedNotification *notification = [self notificationForIndexPath:indexPath];
    if (notification.type == NUANotificationTypeMedia) {
        NUAMediaTableViewCell *mediaCell = [tableView dequeueReusableCellWithIdentifier:@"MediaCell" forIndexPath:indexPath];

        // Provide basic information
        mediaCell.delegate = self;
        mediaCell.expanded = [self isNotificationExpanded:notification];
        mediaCell.layoutMargins = UIEdgeInsetsZero;
        mediaCell.notificationShadePreferences = self.notificationShadePreferences;

        return mediaCell;
    }

    NUANotificationTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NotificationCell" forIndexPath:indexPath];
    cell.notificationShadePreferences = self.notificationShadePreferences;
    cell.notification = notification;
    cell.actionsDelegate = self;
    cell.delegate = self;
    cell.expanded = [self isNotificationExpanded:notification];
    cell.UILocked =  self.UILocked;
    cell.layoutMargins = UIEdgeInsetsZero;

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Block actions on media cell
    return !(indexPath.row == 0 && [self _mediaCellPresent]);
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

#pragma mark - Cells Delegate

- (void)tableViewCell:(NUATableViewCell *)cell wantsExpansion:(BOOL)expand {
    // Get notification
    NUACoalescedNotification *notification; 
    if ([cell isKindOfClass:[NUAMediaTableViewCell class]]) {
        // Dealing with media class
        notification = _mediaNotification;
    } else {
        // Get cell's notification
        NUANotificationTableViewCell *notificationCell = (NUANotificationTableViewCell *)cell;
        notification = notificationCell.notification;
    }

    // Pass along
    [self notification:notification shouldExpand:expand reload:YES];
}

- (void)notification:(NUACoalescedNotification *)notification shouldExpand:(BOOL)expand reload:(BOOL)reload {
    // Add/remove
    if (expand && ![self isNotificationExpanded:notification]) {
        // Add to expanded
        [_expandedNotifications addObject:notification];
    } else if (!expand && [self isNotificationExpanded:notification]) {
        // Add to expanded
        [_expandedNotifications removeObject:notification];
    }

    // Update presented height
    [self _resizeTableForExpansion:expand forNotification:NO];

    if (!reload) {
        return;
    }

    // Reload
    NSIndexPath *indexPath = [self indexPathForNotification:notification];
    [self.tableViewController.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (BOOL)isNotificationExpanded:(NUACoalescedNotification *)notification {
    return [_expandedNotifications containsObject:notification];
}

- (void)notificationTableViewCellRequestsExecuteDefaultAction:(NUANotificationTableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableViewController.tableView indexPathForCell:cell];

    // Launch notif
    [self executeNotificationAction:@"default" forCellAtIndexPath:indexPath];
}

- (void)notificationTableViewCellRequestsExecuteAlternateAction:(NUANotificationTableViewCell *)cell {
    // Figure this out
    NSIndexPath *indexPath = [self.tableViewController.tableView indexPathForCell:cell];

    // Launch notif
    [self executeNotificationAction:@"clear" forCellAtIndexPath:indexPath];
}

#pragma mark - Clear All Button

- (void)_handleClearButtonTouchUpInside:(NUARippleButton *)button {
    if (self.notifications.count == 0) {
        // Nothing to remove
        return;
    }

    // Clear all notifications
    [self.notificationRepository purgeAllNotifications];
}

@end