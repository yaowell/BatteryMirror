#import "BMPRootListController.h"
#import <notify.h>

static NSString * const kBMPrefsDomain = @"com.futur3sn0w.batterymirror.preferences";
static NSString * const kBMReloadNotification = @"com.futur3sn0w.batterymirror/ReloadPrefs";

@implementation BMPRootListController

- (PSSpecifier *)groupSpecifierWithName:(NSString *)name footer:(NSString *)footerText {
	PSSpecifier *specifier = [PSSpecifier emptyGroupSpecifier];
	if (name.length > 0) {
		[specifier setProperty:name forKey:@"label"];
	}
	if (footerText.length > 0) {
		[specifier setProperty:footerText forKey:@"footerText"];
	}
	return specifier;
}

- (PSSpecifier *)switchSpecifierWithName:(NSString *)name key:(NSString *)key defaultValue:(BOOL)defaultValue {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
		target:self
		set:@selector(setPreferenceValue:specifier:)
		get:@selector(readPreferenceValue:)
		detail:Nil
		cell:PSSwitchCell
		edit:Nil];
	[specifier setProperty:kBMPrefsDomain forKey:@"defaults"];
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:@(defaultValue) forKey:@"default"];
	[specifier setProperty:kBMReloadNotification forKey:@"PostNotification"];
	return specifier;
}

- (BOOL)isGloballyEnabled {
	id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)@"Enabled", (__bridge CFStringRef)kBMPrefsDomain));
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

- (void)updateChildSpecifierAvailability {
	BOOL enabled = [self isGloballyEnabled];
	for (PSSpecifier *specifier in _specifiers) {
		NSString *key = [specifier propertyForKey:@"key"];
		if (key.length == 0 || [key isEqualToString:@"Enabled"]) {
			continue;
		}

		[specifier setProperty:@(enabled) forKey:PSEnabledKey];
	}
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	id defaultValue = [specifier propertyForKey:@"default"];
	id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kBMPrefsDomain));
	return value ?: defaultValue;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kBMPrefsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)kBMPrefsDomain);
	notify_post([kBMReloadNotification UTF8String]);

	if ([key isEqualToString:@"Enabled"]) {
		[self updateChildSpecifierAvailability];
		[self reloadSpecifiers];
	}
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [@[
			[self groupSpecifierWithName:nil footer:nil],
			[self switchSpecifierWithName:@"Enabled" key:@"Enabled" defaultValue:YES]
		] mutableCopy];
		[self updateChildSpecifierAvailability];
	}

	return _specifiers;
}

@end
