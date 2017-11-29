//
//  RCTContactsWrapper.m
//  RCTContactsWrapper
//
//  Created by Oliver Jacobs on 15/06/2016.
//  Copyright © 2016 Facebook. All rights reserved.
//

@import Foundation;
#import "RCTContactsWrapper.h"
@interface RCTContactsWrapper()

@property(nonatomic, retain) RCTPromiseResolveBlock _resolve;
@property(nonatomic, retain) RCTPromiseRejectBlock _reject;

@end


@implementation RCTContactsWrapper

int _requestCode;
const int REQUEST_CONTACT = 1;
const int REQUEST_EMAIL = 2;


RCT_EXPORT_MODULE(ContactsWrapper);

/* Get basic contact data as JS object */
RCT_EXPORT_METHOD(getContact:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
  {
    self._resolve = resolve;
    self._reject = reject;
    _requestCode = REQUEST_CONTACT;
    
    [self launchContacts];
    
    
  }

/* Get ontact email as string */
RCT_EXPORT_METHOD(getEmail:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
  self._resolve = resolve;
  self._reject = reject;
  _requestCode = REQUEST_EMAIL;
  
  [self launchContacts];
  
  
}


/**
 Launch the contacts UI
 */
-(void) launchContacts {
  
  UIViewController *picker;
  if([CNContactPickerViewController class]) {
    //iOS 9+
    picker = [[CNContactPickerViewController alloc] init];
    ((CNContactPickerViewController *)picker).delegate = self;
  } else {
    //iOS 8 and below
    picker = [[ABPeoplePickerNavigationController alloc] init];
    [((ABPeoplePickerNavigationController *)picker) setPeoplePickerDelegate:self];
  }
  //Launch Contact Picker or Address Book View Controller
  UIViewController *root = [[[UIApplication sharedApplication] delegate] window].rootViewController;
  BOOL modalPresent = (BOOL) (root.presentedViewController);
  if (modalPresent) {
	  UIViewController *parent = root.presentedViewController;
	  [parent presentViewController:picker animated:YES completion:nil];
  } else {
	  [root presentViewController:picker animated:YES completion:nil];
  }
  
}


#pragma mark - RN Promise Events

- (void)pickerCancelled {
  self._reject(@"E_CONTACT_CANCELLED", @"Cancelled", nil);
}


- (void)pickerError {
  self._reject(@"E_CONTACT_EXCEPTION", @"Unknown Error", nil);
}

- (void)pickerNoEmail {
  self._reject(@"E_CONTACT_NO_EMAIL", @"No email found for contact", nil);
}

-(void)emailPicked:(NSString *)email {
  self._resolve(email);
}


-(void)contactPicked:(NSDictionary *)contactData {
  self._resolve(contactData);
}


#pragma mark - Shared functions


- (NSMutableDictionary *) emptyContactDict {
  return [[NSMutableDictionary alloc] initWithObjects:@[@"", @"", @""] forKeys:@[@"name", @"phone", @"email"]];
}

/**
 Return full name as single string from first last and middle name strings, which may be empty
 */
-(NSString *) getFullNameForFirst:(NSString *)fName middle:(NSString *)mName last:(NSString *)lName {
  //Check whether to include middle name or not
  NSArray *names = (mName.length > 0) ? [NSArray arrayWithObjects:fName, mName, lName, nil] : [NSArray arrayWithObjects:fName, lName, nil];;
  return [names componentsJoinedByString:@" "];
}



#pragma mark - Event handlers - iOS 9+
- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContact:(CNContact *)contact {
  switch(_requestCode){
    case REQUEST_CONTACT:
    {
      /* Return NSDictionary ans JS Object to RN, containing basic contact data
       This is a starting point, in future more fields should be added, as required.
       This could also be extended to return arrays of phone numbers, email addresses etc. instead of jsut first found
       */
      NSMutableDictionary *contactData = [self emptyContactDict];
      
      NSString *fullName = [self getFullNameForFirst:contact.givenName middle:contact.middleName last:contact.familyName ];
      NSArray *phoneNos = contact.phoneNumbers;
      NSArray *emailAddresses = contact.emailAddresses;
//      NSArray *postalAddresses = contact.postalAddresses;
      //Return full name
      [contactData setValue:fullName forKey:@"name"];
      
      //if we have phone numbers
      if([phoneNos count] > 0) {
        NSMutableArray *jsPhoneNumbers = [NSMutableArray array];
        for (CNPhoneNumber* p in phoneNos)
          {
            NSMutableDictionary* dict = @{}.mutableCopy;
            NSLog(@"%@",p);
            CNPhoneNumber *phone = ((CNLabeledValue *)p).value;
            NSString *label = ((CNLabeledValue *)p).label;
            label = [CNLabeledValue localizedStringForLabel:label];
            [dict setValue:phone.stringValue forKey:@"phone"];
            [dict setValue:label forKey:@"phone_label"];
            [jsPhoneNumbers addObject:dict];
          }
        [contactData setValue:jsPhoneNumbers forKey:@"phones"];
      }
      
      //Return first email address
      if([emailAddresses count] > 0) {
        NSMutableArray *jsEmails = [NSMutableArray array];
        for (CNLabeledValue* e in emailAddresses)
        {
          NSMutableDictionary* dict = @{}.mutableCopy;
          CNLabeledValue *email = ((CNLabeledValue *)e).value;
          NSString *label = ((CNLabeledValue *)e).label;
          label = [CNLabeledValue localizedStringForLabel:label];
          [dict setValue:email forKey:@"email"];
          [dict setValue:label forKey:@"email_label"];
          [jsEmails addObject:dict];
        }
        [contactData setValue:jsEmails forKey:@"emails"];
      }
      
      [self contactPicked:contactData];
    }
      break;
    case REQUEST_EMAIL :
    {
      /* Return Only email address as string */
      if([contact.emailAddresses count] < 1) {
        [self pickerNoEmail];
        return;
      }
      
      CNLabeledValue *email = contact.emailAddresses[0].value;
      [self emailPicked:email];
    }
      break;
    default:
      //Should never happen, but just in case, reject promise
      [self pickerError];
    break;
  }
  
  
}


- (void)contactPickerDidCancel:(CNContactPickerViewController *)picker {
  [self pickerCancelled];
}



#pragma mark - Event handlers - iOS 8

/* Same functionality as above, implemented using iOS8 AddressBook library */
- (void)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker didSelectPerson:(ABRecordRef)person {
  switch(_requestCode) {
    case(REQUEST_CONTACT):
    {
      
      /* Return NSDictionary ans JS Object to RN, containing basic contact data
       This is a starting point, in future more fields should be added, as required.
       This could also be extended to return arrays of phone numbers, email addresses etc. instead of jsut first found
       */
      NSMutableDictionary *contactData = [self emptyContactDict];
            NSString *fNameObject, *mNameObject, *lNameObject;
      fNameObject = (__bridge NSString *) ABRecordCopyValue(person, kABPersonFirstNameProperty);
      mNameObject = (__bridge NSString *) ABRecordCopyValue(person, kABPersonMiddleNameProperty);
      lNameObject = (__bridge NSString *) ABRecordCopyValue(person, kABPersonLastNameProperty);
      
      NSString *fullName = [self getFullNameForFirst:fNameObject middle:mNameObject last:lNameObject];
      
      //Return full name
      [contactData setValue:fullName forKey:@"name"];
      
      //Return first phone number
      ABMultiValueRef phoneMultiValue = ABRecordCopyValue(person, kABPersonPhoneProperty);
      NSArray *phoneNos = (__bridge NSArray *)ABMultiValueCopyArrayOfAllValues(phoneMultiValue);
      if([phoneNos count] > 0) {
        [contactData setValue:phoneNos[0] forKey:@"phone"];
      }
     
      //Return first email
      ABMultiValueRef emailMultiValue = ABRecordCopyValue(person, kABPersonEmailProperty);
      NSArray *emailAddresses = (__bridge NSArray *)ABMultiValueCopyArrayOfAllValues(emailMultiValue);
      if([emailAddresses count] > 0) {
        [contactData setValue:emailAddresses[0] forKey:@"email"];
      }
      

      [self contactPicked:contactData];
    }
      break;
    case(REQUEST_EMAIL):
    {
      /* Return Only email address as string */
      ABMultiValueRef emailMultiValue = ABRecordCopyValue(person, kABPersonEmailProperty);
      NSArray *emailAddresses = (__bridge NSArray *)ABMultiValueCopyArrayOfAllValues(emailMultiValue);
      if([emailAddresses count] < 1) {
        [self pickerNoEmail];
        return;
      }
      
      [self emailPicked:emailAddresses[0]];
    }
      break;

    default:
      //Should never happen, but just in case, reject promise
      [self pickerError];
      return;
  }
  
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)peoplePicker {
  [self pickerCancelled];
}






@end
