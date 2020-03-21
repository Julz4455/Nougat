#import "NUAPreferenceManager.h"
#import <Macros.h>
#import <Cephei/HBPreferences.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <UIKit/UIWindow+Private.h>

@interface NUAPreferenceManager () {
    HBPreferences *_preferences;

    NUADrawerTheme _currentTheme;
    NSMutableDictionary<NSString *, NUAToggleInfo *> *_toggleInfoDictionary;
}

@property (assign, readonly, nonatomic) BOOL usesSystemAppearance;

@end

@implementation NUAPreferenceManager

+ (instancetype)sharedSettings {
    static NUAPreferenceManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });

    return sharedInstance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _toggleInfoDictionary = [NSMutableDictionary dictionary];

        _preferences = [HBPreferences preferencesForIdentifier:@"com.shade.nougat"];

        [_preferences registerBool:&_enabled default:YES forKey:NUAPreferencesEnabledKey];
        [_preferences registerInteger:(NSInteger *)&_currentTheme default:NUADrawerThemeNexus forKey:NUAPreferencesCurrentThemeKey];
        [_preferences registerBool:&_useExternalColor default:NO forKey:NUAPreferencesUsesExternalColorKey];
        [_preferences registerBool:&_usesSystemAppearance default:NO forKey:NUAPreferencesUsesSystemAppearanceKey];

        NSArray<NSString *> *defaultToggleOrder = [[self class] _defaultEnabledToggles];
        [_preferences registerObject:&_enabledToggles default:defaultToggleOrder forKey:NUAPreferencesTogglesListKey];

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(preferencesWereUpdated) name:HBPreferencesDidChangeNotification object:nil];
        [self preferencesWereUpdated];

        // Migrate if needed
        if ([self _hasLegacyPrefs]) {
            [self _migrateFromLegacyPrefs];
        }

        // Get toggle info
        [self refreshToggleInfo];
    }

    return self;
}

#pragma mark - Properties

- (UIColor *)backgroundColor {
    if (self.usesSystemAppearance) {
        // Derive from system appearance
        if (@available(iOS 13, *)) {
            // To silence warnings
            UITraitCollection *traitCollection = [UIScreen mainScreen].traitCollection;
            BOOL usingDarkAppearance = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
            return usingDarkAppearance ? PixelBackgroundColor : OreoBackgroundColor;
        }
    } 

    // Derive manually
    switch (_currentTheme) {
        case NUADrawerThemeNexus:
            return NexusBackgroundColor;
        case NUADrawerThemePixel:
            return PixelBackgroundColor;
        case NUADrawerThemeOreo:
            return OreoBackgroundColor;
    }
}

- (UIColor *)highlightColor {
    if (self.usesSystemAppearance) {
        // Derive from system appearance
        if (@available(iOS 13, *)) {
            // To silence warnings
            UITraitCollection *traitCollection = [UIScreen mainScreen].traitCollection;
            BOOL usingDarkAppearance = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
            return usingDarkAppearance ? PixelTintColor : OreoTintColor;
        }
    }

    // Derive manually
    switch (_currentTheme) {
        case NUADrawerThemeNexus:
            return NexusTintColor;
        case NUADrawerThemePixel:
            return PixelTintColor;
        case NUADrawerThemeOreo:
            return OreoTintColor;
    }
}

- (UIColor *)textColor {
    if (self.usesSystemAppearance) {
        // Derive from system appearance
        if (@available(iOS 13, *)) {
            // To silence warnings
            return UIColor.labelColor;
        }
    }
    
    // Derive manually
    return (_currentTheme == NUADrawerThemeOreo) ? [UIColor blackColor] : [UIColor whiteColor];
}

- (BOOL)isUsingDark {
    if (self.usesSystemAppearance) {
        // Derive from system appearance
        if (@available(iOS 13, *)) {
            // To silence warnings
            UITraitCollection *traitCollection = [UIScreen mainScreen].traitCollection;
            return traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight;
        }
    }

    return _currentTheme == NUADrawerThemeOreo;
}

#pragma mark - Callbacks

- (void)preferencesWereUpdated {
    // Update toggle info
    [self refreshToggleInfo];

    // Publish general updates
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NUANotificationShadeChangedPreferences" object:nil userInfo:nil];

    // Publish appearance updates
    NSDictionary<NSString *, UIColor *> *colorInfo = @{@"backgroundColor": self.backgroundColor, @"tintColor": self.highlightColor, @"textColor": self.textColor};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NUANotificationShadeChangedBackgroundColor" object:nil userInfo:colorInfo];
}

#pragma mark - Toggles

- (void)refreshToggleInfo {
    NSError *error = nil;
    NSURL *togglesURL = [NSURL fileURLWithPath:@"/Library/Nougat/Toggles/"];
    NSArray<NSURL *> *bundleURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:togglesURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    if (bundleURLs) {
        for (NSURL *bundleURL in bundleURLs) {
            NUAToggleInfo *info = [NUAToggleInfo toggleInfoWithBundleURL:bundleURL];
            if (info) {
                _toggleInfoDictionary[info.identifier] = info;
            }
        }
    } else {
        HBLogError(@"%@", error);
    }

    // Construct disabled toggles
    NSMutableArray<NSString *> *disabledToggles = [NSMutableArray array];
    for (NSString *identifier in _toggleInfoDictionary.allKeys) {
        if ([self.enabledToggles containsObject:identifier]) {
            continue;
        }

        [disabledToggles addObject:identifier];
    }

    _disabledToggles = [disabledToggles copy];
}

- (NUAToggleInfo *)toggleInfoForIdentifier:(NSString *)identifier {
    return _toggleInfoDictionary[identifier];
}

- (NSArray<NSString *> *)_installedToggleIdentifiers {
    return _toggleInfoDictionary.allKeys;
}

#pragma mark - Migration

- (BOOL)_hasLegacyPrefs {
    // Check if toggles list has old keys
    return [self.enabledToggles containsObject:@"do-not-disturb"];
}

- (void)_migrateFromLegacyPrefs {
    // Change old keys into their new equivalent key
    NSArray<NSString *> *oldTogglesList = self.enabledToggles;
    NSMutableArray<NSString *> *newTogglesList = [NSMutableArray array];
    for (NSString *identifier in oldTogglesList) {
        // Exception for low power, data, wifi
        if ([identifier isEqualToString:@"wifi"]) {
            [newTogglesList addObject:@"com.shade.nougat.WiFiToggle"];
        } else if ([identifier isEqualToString:@"cellular-data"]) {
            [newTogglesList addObject:@"com.shade.nougat.DataToggle"];
        } else if ([identifier isEqualToString:@"low-power"]) {
            [newTogglesList addObject:@"com.shade.nougat.BatterySaverToggle"];
        }

        // Get components
        NSArray<NSString *> *components = [identifier componentsSeparatedByString:@"-"];
        NSString *equivalentKey = @"";
        for (NSString *item in components) {
            // Capitalize first letter
            equivalentKey = [equivalentKey stringByAppendingString:item.capitalizedString];
        }

        // Construct and add key
        NSString *updatedKey = [NSString stringWithFormat:@"com.shade.nougat.%@Toggle", equivalentKey];
        [newTogglesList addObject:updatedKey];
    }

    // Add to prefs
    [_preferences setObject:[newTogglesList copy] forKey:NUAPreferencesTogglesListKey];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.shade.nougat/ReloadPrefs"), NULL, NULL, YES);
}

#pragma mark - Convenience Methods

+ (BOOL)_deviceHasNotch {
    if (@available(iOS 11, *)) {
        // Still can be fooled by Little11/LittleX etc, need to find better method
        CGFloat safeAreaBottomEdgeInset = [UIWindow keyWindow].safeAreaInsets.bottom ?: 0.0;
        return safeAreaBottomEdgeInset > 0;
    }

    // Doesn't apply to before iOS 11
    return NO;
}

+ (NSString *)carrierName {
    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = networkInfo.subscriberCellularProvider;
    return carrier.carrierName;
}

+ (NSArray<NSString *> *)_defaultEnabledToggles {
    return @[@"com.shade.nougat.WiFiToggle", @"com.shade.nougat.DataToggle", @"com.shade.nougat.BluetoothToggle", @"com.shade.nougat.DoNotDisturbToggle", @"com.shade.nougat.FlashlightToggle", @"com.shade.nougat.RotationLockToggle", @"com.shade.nougat.BatterySaverToggle", @"com.shade.nougat.LocationToggle", @"com.shade.nougat.AirplaneModeToggle"];
}

@end
