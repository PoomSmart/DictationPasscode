#import <substrate.h>
#import "../PS.h"
#import <Preferences/Preferences.h>
#import <Preferences/PSSpecifier.h>

#define DEBUG

#ifdef DEBUG
	#define PSLog(...) NSLog(@"[DictationPasscode], %@", [NSString stringWithFormat:__VA_ARGS__])
#else
	#define PSLog(...)
#endif

extern NSString *const PSDefaultsKey;
extern NSString *const PSKeyNameKey;
extern NSString *const PSTableCellKey;
extern NSString *const PSDefaultValueKey;
static NSString *const PreferencesDomain = @"com.apple.Preferences";
static NSString *const dpKey = @"KeyboardDictationPasscode";
static NSString *const keyboardPrefPath = @"/var/mobile/Library/Preferences/com.apple.keyboard.plist";

static BOOL dpEnabled()
{
	NSDictionary *prefDict = [NSDictionary dictionaryWithContentsOfFile:keyboardPrefPath] ?: [NSDictionary dictionary];
	return [prefDict[dpKey] boolValue];
}

BOOL hookNotPasscodeStyle = NO;
BOOL hookNotSecureTextEntry = NO;
BOOL hookKeyboardTypeZero = NO;

%group dp7Up

%hook NSObject

- (BOOL)respondsToSelector:(SEL)selector
{
	if (hookNotPasscodeStyle) {
		if (sel_isEqual(selector, @selector(_isPasscodeStyle)))
			return NO;
	}
	return %orig;
}

%end

%hook UIDictationController

+ (void)keyboardWillChangeFromDelegate:(id)arg1 toDelegate:(id)arg2
{
	hookNotPasscodeStyle = dpEnabled();
	%orig;
	hookNotPasscodeStyle = NO;
}

+ (BOOL)dictationIsFunctional
{
	hookNotPasscodeStyle = dpEnabled();
	BOOL orig = %orig;
	PSLog(@"dictationIsFunctional: %d", orig);
	hookNotPasscodeStyle = NO;
	return orig;
}

%end

%hook UIKeyboardLayoutStar

- (BOOL)canReuseKeyplaneView
{
	hookNotSecureTextEntry = YES;
	BOOL orig = %orig;
	hookNotSecureTextEntry = NO;
	PSLog(@"canReuseKeyplaneView: %d", orig);
	return orig;
}

- (void)updateMoreAndInternationalKeys
{
	hookNotSecureTextEntry = YES;
	%orig;
	hookNotSecureTextEntry = NO;
}

%end

%end

%group dp6Up

%hook UITextInputTraits

- (BOOL)isSecureTextEntry
{
	return hookNotSecureTextEntry ? NO : %orig;
}

%end

%end

%group dp56

%hook UIKeyboardLayoutStar

- (BOOL)shouldShowDictationKey
{
	BOOL isSecure = MSHookIvar<BOOL>(self, "_secureTextEntry");
	if (isSecure) {
		MSHookIvar<BOOL>(self, "_secureTextEntry") = !dpEnabled();
		BOOL orig = %orig;
		PSLog(@"shouldShowDictationKey: %d", orig);
		MSHookIvar<BOOL>(self, "_secureTextEntry") = YES;
	}
	return %orig;
}

- (BOOL)canReuseKeyplaneView
{
	BOOL isSecure = MSHookIvar<BOOL>(self, "_secureTextEntry");
	if (isSecure) {
		MSHookIvar<BOOL>(self, "_secureTextEntry") = !dpEnabled();
		BOOL orig = %orig;
		PSLog(@"canReuseKeyplaneView: %d", orig);
		MSHookIvar<BOOL>(self, "_secureTextEntry") = YES;
	}
	return %orig;
}

- (void)updateMoreAndInternationalKeys
{
	BOOL isSecure = MSHookIvar<BOOL>(self, "_secureTextEntry");
	if (isSecure) {
		MSHookIvar<BOOL>(self, "_secureTextEntry") = !dpEnabled();
		%orig;
		MSHookIvar<BOOL>(self, "_secureTextEntry") = YES;
		return;
	}
	%orig;
}

%end

%hook UITextInputTraits

- (int)keyboardType
{
	return hookKeyboardTypeZero ? 0 : %orig;
}

%end

%end

%group dpCommon

%hook UIDictationController

+ (BOOL)fetchCurrentInputModeSupportsDictation
{
	BOOL enabled = dpEnabled();
	hookNotSecureTextEntry = enabled;
	hookKeyboardTypeZero = enabled;
	BOOL orig = %orig;
	PSLog(@"fetchCurrentInputModeSupportsDictation: %d", orig);
	hookNotSecureTextEntry = NO;
	hookKeyboardTypeZero = NO;
	return orig;
}

%end

%end

%group Pref

static char dpSpecifierKey;

@interface KeyboardController : UIViewController
@property (retain, nonatomic, getter=_dp_specifier, setter=_set_dp_specifier:) PSSpecifier *dpSpecifier;
@end

%hook KeyboardController

%new(v@:@)
- (void)_set_dp_specifier:(id)object
{
    objc_setAssociatedObject(self, &dpSpecifierKey, object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new(@@:)
- (id)_dp_specifier
{
    return objc_getAssociatedObject(self, &dpSpecifierKey);
}

%new
- (id)dp_getValue:(PSSpecifier *)specifier
{
	return @(dpEnabled());
}

%new
- (void)dp_setValue:(id)value specifier:(PSSpecifier *)specifier
{
	NSMutableDictionary *prefDict = [[NSDictionary dictionaryWithContentsOfFile:keyboardPrefPath] mutableCopy] ?: [NSMutableDictionary dictionary];
	[prefDict setObject:value forKey:dpKey];
	[prefDict writeToFile:keyboardPrefPath atomically:YES];
}

- (NSMutableArray *)specifiers
{
	if (MSHookIvar<NSMutableArray *>(self, "_specifiers") != nil)
		return %orig();
	NSMutableArray *specifiers = %orig();
	NSUInteger insertionIndex = NSNotFound;
	for (PSSpecifier *spec in specifiers) {
		if ([[spec propertyForKey:@"label"] isEqualToString:@"PERIOD_SHORTCUT"])
			insertionIndex = [specifiers indexOfObject:spec];
	}
	if (insertionIndex == NSNotFound)
		return specifiers;
	insertionIndex++;
	PSSpecifier *dpSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Dictation Passcode" target:self set:@selector(dp_setValue:specifier:) get:@selector(dp_getValue:) detail:nil cell:[PSTableCell cellTypeFromString:@"PSSwitchCell"] edit:nil];
	[dpSpecifier setProperty:PreferencesDomain forKey:PSDefaultsKey];
	[dpSpecifier setProperty:dpKey forKey:PSKeyNameKey];
	[dpSpecifier setProperty:@NO forKey:PSDefaultValueKey];
	[specifiers insertObject:dpSpecifier atIndex:insertionIndex];
	self.dpSpecifier = dpSpecifier;
	return specifiers;
}

%end

%end

%ctor
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL isPrefApp = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:PreferencesDomain];
	if (isPrefApp) {
		dlopen("/System/Library/PreferenceBundles/KeyboardSettings.bundle/KeyboardSettings", RTLD_LAZY);
		%init(Pref);
	} else {
		if (isiOS7Up) {
			%init(dp7Up);
		}
		if (isiOS6Up) {
			%init(dp6Up);
		}
		if (isiOS5 || isiOS6) {
			%init(dp56);
		}
		%init(dpCommon);
	}
	[pool drain];
}
