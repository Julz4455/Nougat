#import "NUASortOrderController.h"
#import "NUAPreferenceManager.h"
#import <Cephei/HBPreferences.h>

@implementation NUASortOrderController

- (NSArray *)specifiers {
    return nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tableView = [[UITableView alloc] initWithFrame:[UIScreen mainScreen].bounds style:UITableViewStyleGrouped];
        self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        self.tableView.editing = YES;
        self.tableView.allowsSelection = YES;
        self.tableView.allowsSelectionDuringEditing = YES;

        _togglesList = [NUAPreferenceManager sharedSettings].togglesList;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view addSubview:self.tableView];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Toggles order";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.togglesList count];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"NougatCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }

    cell.textLabel.text = self.togglesList[indexPath.row];

    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray *array = [self.togglesList mutableCopy];
    NSString *string = array[sourceIndexPath.row];

    [array removeObjectAtIndex:sourceIndexPath.row];
    [array insertObject:string atIndex:destinationIndexPath.row];
    [self setPreferenceValue:[array copy] forKey:NUAPreferencesTogglesListKey];
}


- (void)setPreferenceValue:(id)value forKey:(NSString *)key {
    HBPreferences *preferences = [HBPreferences preferencesForIdentifier:@"com.shade.nougat"];
    [preferences setObject:value forKey:key];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.shade.nougat/ReloadPrefs"), NULL, NULL, YES);
}

@end
