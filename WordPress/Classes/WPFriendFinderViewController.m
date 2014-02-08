/*
 * WPFriendFinderViewController.m
 *
 * Copyright (c) 2013 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import <AddressBook/AddressBook.h>
#import <Accounts/Accounts.h>
#import <Social/Social.h>
#import "WPFriendFinderViewController.h"
#import "Constants.h"

static NSString *const FacebookAppID = @"249643311490";
static NSString *const FacebookLoginNotificationName = @"FacebookLogin";
static NSString *const FacebookNoLoginNotificationName = @"FacebookNoLogin";
static NSString *const AccessedAddressBookPreference = @"AddressBookAccessGranted";

@interface WPFriendFinderViewController ()

@property (nonatomic, strong) UIActivityIndicatorView *activityView;

@end

@implementation WPFriendFinderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self loadURL:kMobileReaderFFURL];
    
    // register for a notification
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(facebookDidLogIn:) name:FacebookLoginNotificationName object:nil];
    [nc addObserver:self selector:@selector(facebookDidNotLogIn:) name:FacebookNoLoginNotificationName object:nil];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(dismissFriendFinder:)];
    self.activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.activityView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
    CGRect f1 = self.activityView.frame;
    CGRect f2 = self.view.frame;
    f1.origin.x = (f2.size.width / 2.0f) - (f1.size.width / 2.0f);
    f1.origin.y = (f2.size.height / 2.0f) - (f1.size.height / 2.0f);
    self.activityView.frame = f1;
    
    [self.view addSubview:self.activityView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.activityView = nil;
}

- (void)dismissFriendFinder:(id)sender {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)configureFriendFinder:(id)config {
    NSDictionary *settings = (NSDictionary *)config;
    NSArray *sources = (NSArray *)[settings objectForKey:@"sources"];
    
    NSMutableArray *available = [NSMutableArray arrayWithObjects:@"address-book", @"facebook", nil];
    
    if ([sources containsObject:@"twitter"]){
        [available addObject:@"twitter"];
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:available options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"FriendFinder.enableSources(%@)", json]];
}

- (void)authorizeSource:(NSString *)source {
    if ([source isEqualToString:@"address-book"]) {
        [self findEmails];
    } else if ([source isEqualToString:@"twitter"]) {
        [self findTwitterFriends];
    } else if ([source isEqualToString:@"facebook"]){
        [self findFacebookFriends];
    }
}

- (void)findEmails {
    ABAddressBookRef addressBookForAccessCheck = ABAddressBookCreateWithOptions(NULL, NULL);
    if (addressBookForAccessCheck) {
        addressBookForAccessCheck = CFAutorelease(addressBookForAccessCheck);
        ABAddressBookRequestAccessWithCompletion(addressBookForAccessCheck, ^(bool granted, CFErrorRef error) {
            if (granted) {
                ABAddressBookRef addressBook = ABAddressBookCreateWithOptions(NULL, NULL);
                addressBook = CFAutorelease(addressBook);
                CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);
                CFIndex count = CFArrayGetCount(people);
                NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:count];

                for (CFIndex i = 0; i < count; i++) {
                    ABRecordRef person = CFArrayGetValueAtIndex(people, i);
                    ABMultiValueRef emails = ABRecordCopyValue(person, kABPersonEmailProperty);
                    for (CFIndex j = 0; j<ABMultiValueGetCount(emails); j++) {
                        NSString *email = (NSString *)CFBridgingRelease(ABMultiValueCopyValueAtIndex(emails, j));
                        [addresses addObject:email];
                    }
                    CFRelease(emails);
                }
                CFRelease(people);

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (addresses.count == 0) {
                        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Contacts", @"Title of an alert warning the user that the address book does not contain any contacts.")
                                                                            message:NSLocalizedString(@"No contacts were found in your address book.", @"")
                                                                           delegate:self
                                                                  cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                                  otherButtonTitles:nil];
                        [alertView show];
                        [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByEmail()"];
                    } else {
                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:addresses options:0 error:nil];
                        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                        [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"FriendFinder.findByEmail(%@)", json]];
                    }
                });
            } else {
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Access To Address Book", @"Title of an alert warning the user that the WordPress app is not authorized to access her address book.")
                                                                    message:NSLocalizedString(@"In order to search your address book, please grant the WordPress app access to your Contacts in the Settings app.", @"")
                                                                   delegate:self
                                                          cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                          otherButtonTitles:nil];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByEmail()"];
                    [alertView show];
                });
            }
        });
    } else {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Access To Address Book", @"Title of an alert warning the user that the WordPress app is not authorized to access her address book.")
                                                            message:NSLocalizedString(@"In order to search your address book, please grant the WordPress app access to your Contacts in the Settings app.", @"")
                                                           delegate:self
                                                  cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                  otherButtonTitles:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByEmail()"];
            [alertView show];
        });
    }
}

- (void)findTwitterFriends {
    ACAccountStore *store = [[ACAccountStore alloc] init];
    ACAccountType *twitterAccountType = 
    [store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    [store requestAccessToAccountsWithType:twitterAccountType options:nil completion:^(BOOL granted, NSError *error) {
        
        if (granted) {
            NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"true", @"stringify_ids",
                                    @"-1", @"cursor",
                                    nil];
            
            NSURL *followingURL = [NSURL URLWithString:@"https://api.twitter.com/1.1/friends/ids.json"];
            NSArray *twitterAccounts = [store accountsWithAccountType:twitterAccountType];
            if (twitterAccounts.count == 0) {
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Twitter Account", @"Title of an alert warning the user that no Twitter account was registered on the device.")
                                                                    message:NSLocalizedString(@"In order to use Twitter functionality, please add your Twitter account in the Settings app.", @"")
                                                                   delegate:self
                                                          cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                          otherButtonTitles:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByTwitterID()"];
                    [alertView show];
                });
            } else {
                [twitterAccounts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    ACAccount *account = (ACAccount *)obj;
                    SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter
                                                            requestMethod:SLRequestMethodGET
                                                                      URL:followingURL
                                                               parameters:params];
                    request.account = account;
                    [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
                        NSString *responseJSON = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"FriendFinder.findByTwitterID(%@, '%@')", responseJSON, account.accountDescription]];
                        });
                    }];
                }];
            }
        } else {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Twitter Access", @"Title of an alert warning the user that the WordPress app is not authorized to access her Twitter accounts.")
                                                                message:NSLocalizedString(@"In order to use Twitter functionality, please grant the WordPress app access to your Twitter account in the Settings app.", @"")
                                                               delegate:self
                                                      cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                      otherButtonTitles:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByTwitterID()"];
                [alertView show];
            });
        }
    }];
}

- (void)facebookDidLogIn:(NSNotification *)notification {
    [self findFacebookFriends];
}

- (void)facebookDidNotLogIn:(NSNotification *)notification {
    [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByFacebookID()"];
}

- (void)findFacebookFriends {
    ACAccountStore *store = [[ACAccountStore alloc] init];

    NSDictionary *options = @{
                              ACFacebookAppIdKey: FacebookAppID,
                              ACFacebookPermissionsKey: @[@"email"]
                              };
    [store requestAccessToAccountsWithType:[store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierFacebook] options:options completion:^(BOOL granted, NSError *error) {
        if (granted) {
            NSArray *facebookAccounts = [store accountsWithAccountType:[store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierFacebook]];
            [facebookAccounts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                ACAccount *account = (ACAccount *)obj;
                NSURL *friendsURL = [NSURL URLWithString:@"https://graph.facebook.com/me/friends"];
                SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeFacebook
                                                        requestMethod:SLRequestMethodGET
                                                                  URL:friendsURL
                                                           parameters:nil];
                request.account = account;
                [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
                    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
                    if (response && [response isKindOfClass:[NSDictionary class]]) {
                        NSArray *friends = response[@"data"];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:friends options:0 error:nil];
                            NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                            [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"FriendFinder.findByFacebookID(%@)", json]];
                        });
                    }
                }];
            }];
        } else {
            UIAlertView *alertView;
            if (error.code == ACErrorAccountNotFound) {
                alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Facebook Account", @"Title of an alert warning the user that no Facebook account was registered on the device.")
                                                                    message:NSLocalizedString(@"In order to use Facebook functionality, please add your Facebook account in the Settings app.", @"")
                                                                   delegate:self
                                                          cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                          otherButtonTitles:nil];
            } else {
                alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Facebook Access", @"Title of an alert warning the user that the WordPress app is not authorized to access her Facebook accounts.")
                                                                    message:NSLocalizedString(@"In order to use Facebook functionality, please grant the WordPress app access to your Facebook account in the Settings app.", @"")
                                                                   delegate:self
                                                          cancelButtonTitle:NSLocalizedString(@"OK",@"")
                                                          otherButtonTitles:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertView show];
                [self.webView stringByEvaluatingJavaScriptFromString:@"FriendFinder.findByFacebookID()"];
            });
        }
    }];
}

#pragma mark - UIWebView Delegate Methods

- (void)webViewDidStartLoad:(UIWebView *)webView {
    if ([[[webView stringByEvaluatingJavaScriptFromString:@"document.body.innerHTML.length"] numericValue] integerValue] == 0) {
        [self.activityView startAnimating];
    }
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self.activityView stopAnimating];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    [self.activityView stopAnimating];
}

@end
