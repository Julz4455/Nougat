#import "NUASortOrderController.h"
#import "NUASortOrderHeaderView.h"
#import "NUAToggleTableCell.h"
#import "NUAToggleDescription.h"
#import <Cephei/HBPreferences.h>
#import <UIKit/UIImage+Private.h>

@interface NUASortOrderController ()
@property (strong, nonatomic) NSMutableArray<NSString *> *enabledIdentifiers;
@property (strong, nonatomic) NSMutableArray<NSString *> *disabledIdentifiers;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NUAToggleDescription *> *identifiersToDescription;

@end

@implementation NUASortOrderController

#pragma mark - Init

- (instancetype)init {
    self = [super init];
    if (self) {
        // Configure viewcontroller
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        self.title = [bundle localizedStringForKey:@"CUSTOMIZE_TOGGLES_DETAILS_TITLE" value:@"Sort Order" table:@"SortOrder"];

        if (@available(iOS 11, *)) {
            // iOS 11 only
            self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
        }

        // Create arrays
        _enabledIdentifiers = [NSMutableArray array];
        _disabledIdentifiers = [NSMutableArray array];
        _identifiersToDescription = [NSMutableDictionary dictionary];

        // Set prefs
        _preferences = [NUAPreferenceManager sharedSettings];

        // Create tableview
        _tableViewController = [[UITableViewController alloc] initWithStyle:UITableViewStyleGrouped];
        [_tableViewController setEditing:YES animated:NO];

        // Populate data
        [self _repopulateToggleData];
    }

    return self;
}

#pragma mark - Toggles

- (void)_repopulateToggleData {
    // Construct descriptions
    for (NSString *identifier in self.preferences.loadableToggleIdentifiers) {
        NUAToggleInfo *toggleInfo = [self.preferences toggleInfoForIdentifier:identifier];
        NSBundle *toggleBundle = [NSBundle bundleWithURL:toggleInfo.toggleBundleURL];

        NSString *displayName = [self _displayNameFromBundle:toggleBundle];
        UIImage *settingsIcon = [self _iconFromBundle:toggleBundle];
        NUAToggleDescription *toggleDescription = [NUAToggleDescription descriptionWithIdentifier:toggleInfo.toggleIdentifier displayName:displayName iconImage:settingsIcon];

        self.identifiersToDescription[toggleDescription.identifier] = toggleDescription;
    }

    // Set enabled list
    _enabledIdentifiers = [self.preferences.enabledToggleIdentifiers mutableCopy];

    // Get disabled list
    NSSet<NSString *> *tempEnabledSet = [NSSet setWithArray:[self.enabledIdentifiers copy]];
    NSMutableSet<NSString *> *disabledIdentifiers = [self.preferences.loadableToggleIdentifiers mutableCopy];
    [disabledIdentifiers minusSet:tempEnabledSet]; 

    // Sort by display name
    NSArray<NSString *> *currentDisabledToggles = disabledIdentifiers.allObjects;
    NSMutableArray<NSString *> *displayNamesArray = [NSMutableArray array];
    for (NSString *identifier in currentDisabledToggles) {
        NSString *displayName = [self _displayNameForIdentifier:identifier];
        NSString *sortedNameEntry = [NSString stringWithFormat:@"%@|%@", displayName, identifier];
        [displayNamesArray addObject:sortedNameEntry];
    }

    // Alphabetize
    NSArray<NSString *> *sortedDisplayName = [displayNamesArray sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<NSString *> *sortedDisabledToggles = [NSMutableArray array];
    for (NSString *entry in sortedDisplayName) {
        // Get identifier from entry
        NSArray<NSString *> *components = [entry componentsSeparatedByString:@"|"];
        [sortedDisabledToggles addObject:components[1]];
    }

    _disabledIdentifiers = sortedDisabledToggles;
}

#pragma mark - PSViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Create header view
    NUASortOrderHeaderView *headerView = [[NUASortOrderHeaderView alloc] initWithFrame:CGRectZero];
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *fallbackText = @"Add and organize additional toggles to appear in Nougat. Nougat allows up to a maximum of 9 toggles.";
    headerView.text = [bundle localizedStringForKey:@"CUSTOMIZE_TOGGLES_DETAILS_HEADER" value:fallbackText table:@"SortOrder"];

    // Configure tableView
    [self addChildViewController:self.tableViewController];
    self.tableViewController.tableView.dataSource = self;
    self.tableViewController.tableView.delegate = self;
    self.tableViewController.tableView.estimatedRowHeight = [UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight;

    // Register custom cell class
    [self.tableViewController.tableView registerClass:[NUAToggleTableCell class] forCellReuseIdentifier:@"NougatCell"];

    // Update insets
    CGFloat topInset = CGRectGetHeight(self.navigationController.navigationBar.frame);
    UIEdgeInsets oldInsets = self.tableViewController.tableView.contentInset;
    self.tableViewController.tableView.contentInset = UIEdgeInsetsMake(topInset, oldInsets.left, oldInsets.bottom, oldInsets.right);

    // Add header view
    self.tableViewController.tableView.tableHeaderView = headerView;
    [headerView sizeToFit];

    [self.view addSubview:self.tableViewController.tableView];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    // Save settings
    [self _updateEnabledToggles];
}

#pragma mark - Helper Methods

- (NSMutableArray<NSString *> *)arrayForSection:(NSInteger)section {
    return (section == 0) ? self.enabledIdentifiers : self.disabledIdentifiers;
}

- (NSString *)_displayNameForIdentifier:(NSString *)identifier {
    return [self _descriptionForIdentifier:identifier].displayName;
}

- (NSUInteger)_indexForInsertingItemWithIdentifier:(NSString *)identifier intoArray:(NSArray<NSString *> *)array {
    return [array indexOfObject:identifier inSortedRange:NSMakeRange(0, array.count) options:NSBinarySearchingInsertionIndex usingComparator:^(NSString *id1, NSString *id2) {
        NSString *displayName1 = [self _displayNameForIdentifier:id1];
        NSString *displayName2 = [self _displayNameForIdentifier:id2];

        return [displayName1 compare:displayName2];
    }];
}

- (NSString *)_displayNameFromBundle:(NSBundle *)bundle {
    NSString *displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (!displayName) {
        // Fall back to bundle name
        displayName = [bundle objectForInfoDictionaryKey:(__bridge_transfer NSString *)kCFBundleNameKey];
    }

    if (!displayName) {
        // Fall back to executable name
        displayName = [bundle objectForInfoDictionaryKey:(__bridge_transfer NSString *)kCFBundleExecutableKey];
    }

    if (!displayName) {
        // Fall back to bundle identifier
        displayName = bundle.bundleIdentifier;
    }

    return displayName;
}

- (UIImage *)_iconFromBundle:(NSBundle *)bundle {
    UIImage *settingsIcon = [UIImage imageNamed:@"SettingsIcon" inBundle:bundle];
    if (!settingsIcon) {
        // Provide fallback icon
        settingsIcon = [UIImage imageNamed:@"FallbackSettingsIcon" inBundle:[NSBundle bundleForClass:self.class]];
    }

    return settingsIcon;
}

- (NSString *)_identifierAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray<NSString *> *sectionIdentifiers = [self arrayForSection:indexPath.section];
    return sectionIdentifiers[indexPath.row];
}

- (NUAToggleDescription *)_descriptionForIdentifier:(NSString *)identifier {
    return self.identifiersToDescription[identifier];
}

- (NUAToggleDescription *)_descriptionAtIndexPath:(NSIndexPath *)indexPath {
    return [self _descriptionForIdentifier:[self _identifierAtIndexPath:indexPath]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self arrayForSection:section].count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"NougatCell";
    NUAToggleTableCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    // Customize cell
    NUAToggleDescription *toggleDescription = [self _descriptionAtIndexPath:indexPath];
    cell.toggleDescription = toggleDescription;

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    switch (section) {
        case 0:
            return [bundle localizedStringForKey:@"ENABLED_MODULES_SECTION_TITLE" value:@"Include" table:@"SortOrder"];
        case 1:
            return [bundle localizedStringForKey:@"DISABLED_MODULES_SECTION_TITLE" value:@"More Toggles" table:@"SortOrder"];
        default:
            return @"";
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleInsert) {
        if (self.enabledIdentifiers.count >= 9) {
            // Dont add more than 9 toggles
            return;
        }

        // Move from disabled to enabled
        NSString *identifier = self.disabledIdentifiers[indexPath.row];
        NSUInteger insertIndex = self.enabledIdentifiers.count;
        [self.disabledIdentifiers removeObject:identifier];
        [self.enabledIdentifiers addObject:identifier];

        // Update table
        [tableView beginUpdates];

        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:insertIndex inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];

        [tableView endUpdates];
    } else if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Move from enabled to disabled
        NSString *identifier = self.enabledIdentifiers[indexPath.row];
        NSUInteger insertIndex = [self _indexForInsertingItemWithIdentifier:identifier intoArray:self.disabledIdentifiers];

        [self.enabledIdentifiers removeObject:identifier];
        [self.disabledIdentifiers insertObject:identifier atIndex:insertIndex];

        // Update table
        [tableView beginUpdates];

        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:insertIndex inSection:1]] withRowAnimation:UITableViewRowAnimationAutomatic];

        [tableView endUpdates];
    }

    [self _updateEnabledToggles];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.section == 0);
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray<NSString *> *sourceArray = [self arrayForSection:sourceIndexPath.section];
    NSMutableArray<NSString *> *destinationArray = [self arrayForSection:destinationIndexPath.section];
    NSString *identifier = sourceArray[sourceIndexPath.row];

    [sourceArray removeObjectAtIndex:sourceIndexPath.row];
    [destinationArray insertObject:identifier atIndex:destinationIndexPath.row];

    [self.tableViewController.tableView reloadData];
    [self _updateEnabledToggles];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return UITableViewCellEditingStyleDelete;
        case 1:
            return UITableViewCellEditingStyleInsert;
        default:
            return UITableViewCellEditingStyleNone;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    return [bundle localizedStringForKey:@"CUSTOMIZE_TOGGLES_REMOVE" value:@"Remove" table:@"SortOrder"];
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section != 1) {
        // Inserting into enabled, no need to alphabetize
        return proposedDestinationIndexPath;
    }

    // Get index of proper alphabetical order
    NSString *identifier = self.enabledIdentifiers[sourceIndexPath.row];
    NSUInteger insertIndex = [self _indexForInsertingItemWithIdentifier:identifier intoArray:self.disabledIdentifiers];

    return [NSIndexPath indexPathForRow:insertIndex inSection:1];
}

#pragma mark - Preferences

- (void)_updateEnabledToggles {
    // Update HBPreferences
    HBPreferences *preferences = [HBPreferences preferencesForIdentifier:@"com.shade.nougat"];
    preferences[NUAPreferencesTogglesListKey] = [self.enabledIdentifiers copy];

    // Post notification
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.shade.nougat/ReloadPrefs"), NULL, NULL, YES);
}

@end
