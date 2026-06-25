#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface BMPRootListController : PSListController
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end
