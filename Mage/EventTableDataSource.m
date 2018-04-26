//
//  EventTableDataSource.m
//  MAGE
//
//

#import "EventTableDataSource.h"
#import "Event.h"
#import "User.h"
#import "Server.h"
#import "EventChooserController.h"
#import "Observation.h"
#import "EventTableViewCell.h"
#import "Theme+UIResponder.h"
#import "EventTableHeaderView.h"

@interface EventTableDataSource()

@property (strong, nonatomic) NSDictionary *eventIdToOfflineObservationCount;
@property (strong, nonatomic) NSString *currentFilter;

@end

@implementation EventTableDataSource

// This method should not be called until the events have been loaded from the server
- (void) startFetchController {
    
    User *current = [User fetchCurrentUserInManagedObjectContext:[NSManagedObjectContext MR_defaultContext]];
    NSArray *recentEventIds = [NSArray arrayWithArray:current.recentEventIds];
    self.otherFetchedResultsController = [Event caseInsensitiveSortFetchAll:@"name" ascending:YES withPredicate:[NSPredicate predicateWithFormat:@"NOT (remoteId IN %@)", recentEventIds] groupBy:nil delegate:self inContext:[NSManagedObjectContext MR_defaultContext]];
    
    self.otherFetchedResultsController.accessibilityLabel = @"Other Events";
    
    self.recentFetchedResultsController = [Event caseInsensitiveSortFetchAll:@"name" ascending:YES withPredicate:[NSPredicate predicateWithFormat:@"(remoteId IN %@)", recentEventIds] groupBy:nil delegate:self inContext:[NSManagedObjectContext MR_defaultContext]];
    
    self.recentFetchedResultsController.accessibilityLabel = @"My Recent Events";

    NSError *error;
    if (![self.otherFetchedResultsController performFetch:&error]) {
        // Update to handle the error appropriately.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        exit(-1);  // Fail
    }
    
    if (![self.recentFetchedResultsController performFetch:&error]) {
        // Update to handle the error appropriately.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        exit(-1);  // Fail
    }
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[Observation MR_entityName]];
    
    NSExpression *eventExpression = [NSExpression expressionForKeyPath:@"eventId"];
    NSExpressionDescription *countExpression = [[NSExpressionDescription alloc] init];
    
    countExpression.name = @"count";
    countExpression.expression = [NSExpression expressionForFunction:@"count:" arguments:@[eventExpression]];
    countExpression.expressionResultType = NSInteger64AttributeType;
    
    request.resultType = NSDictionaryResultType;
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES]];
    request.propertiesToGroupBy = @[@"eventId"];
    request.propertiesToFetch = @[@"eventId", countExpression];
    request.predicate = [NSPredicate predicateWithFormat:@"error != nil"];
    
    NSArray *groups = [[NSManagedObjectContext MR_defaultContext] executeFetchRequest:request error:nil];
    NSMutableDictionary *offlineCount = [[NSMutableDictionary alloc] init];
    for (NSDictionary *group in groups) {
        [offlineCount setObject:[group objectForKey:@"count"] forKey:[group objectForKey:@"eventId"]];
    }
    self.eventIdToOfflineObservationCount = offlineCount;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.filteredFetchedResultsController) {
        return self.filteredFetchedResultsController.fetchedObjects.count;
    }
    if (section == 1) {
        return self.recentFetchedResultsController.fetchedObjects.count;
    } else if (section == 2) {
        return self.otherFetchedResultsController.fetchedObjects.count;
    }
    return 0;
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.filteredFetchedResultsController != nil) return 1;
    if (self.otherFetchedResultsController.fetchedObjects.count == 0 && self.recentFetchedResultsController.fetchedObjects.count == 0) return 0;
    return 3;
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.filteredFetchedResultsController) {
        return [NSString stringWithFormat:@"%@ (%lu)", self.filteredFetchedResultsController.accessibilityLabel, (unsigned long)self.filteredFetchedResultsController.fetchedObjects.count];
    }
    if (section == 1) {
        return [NSString stringWithFormat:@"%@ (%lu)", self.recentFetchedResultsController.accessibilityLabel, (unsigned long)self.recentFetchedResultsController.fetchedObjects.count];
    } else if (section == 2) {
        return [NSString stringWithFormat:@"%@ (%lu)", self.otherFetchedResultsController.accessibilityLabel, (unsigned long)self.otherFetchedResultsController.fetchedObjects.count];
    }
    return nil;
}

- (void) setEventFilter: (NSString *) filter {
    if (!filter) {
        self.filteredFetchedResultsController = nil;
        return;
    }
    self.filteredFetchedResultsController = [Event caseInsensitiveSortFetchAll:@"name" ascending:YES withPredicate:[NSPredicate predicateWithFormat:@"name contains[cd] %@", filter] groupBy:nil delegate:self inContext:[NSManagedObjectContext MR_defaultContext]];
    
    self.filteredFetchedResultsController.accessibilityLabel = @"Filtered";
    NSError *error;
    if (![self.filteredFetchedResultsController performFetch:&error]) {
        // Update to handle the error appropriately.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        exit(-1);  // Fail
    }
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    EventTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"eventCell"];
    Event *event = nil;
    
    if (self.filteredFetchedResultsController != nil) {
        event = [self.filteredFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    } else if (indexPath.section == 1) {
        event = [self.recentFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    } else if (indexPath.section == 2) {
        event = [self.otherFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    }
    
    [cell populateCellWithEvent:event offlineObservationCount:[[self.eventIdToOfflineObservationCount objectForKey:event.remoteId] integerValue]];
    
    return cell;
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    Event *event = nil;
    if (self.filteredFetchedResultsController != nil) {
        event = [self.filteredFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    } else if (indexPath.section == 1) {
        event = [self.recentFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    } else if (indexPath.section == 2) {
        event = [self.otherFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    }
    if (event.eventDescription) {
        return 72.0f;
    }
    return 48.0f;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Event *event = nil;
    if (self.filteredFetchedResultsController != nil) {
        event = [self.filteredFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    } else if (indexPath.section == 1) {
        event = [self.recentFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    } else if (indexPath.section == 2) {
        event = [self.otherFetchedResultsController.fetchedObjects objectAtIndex:indexPath.row];
    }

    [Server setCurrentEventId:event.remoteId];
    [self.eventSelectionDelegate didSelectEvent:event];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return 80.0f;
    }
    return CGFLOAT_MIN;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.filteredFetchedResultsController != nil) {
        return 48.0f;
    }
    
    if (section == 0) return CGFLOAT_MIN;
    
    if (section == 1 && self.recentFetchedResultsController.fetchedObjects.count == 0) return CGFLOAT_MIN;
    
    if (section == 2 && self.otherFetchedResultsController.fetchedObjects.count == 0) return CGFLOAT_MIN;
   
    return 48.0f;
}

- (NSString *) tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.filteredFetchedResultsController != nil) {
        return @"End of Results";
    }
    if (section == 0) {
        if (self.recentFetchedResultsController.fetchedObjects.count == 0 && self.otherFetchedResultsController.fetchedObjects.count > 1) {
            return @"Welcome to MAGE.  Please choose an event.  The observations you create and your reported location will be part of the selected event.  You can change your event at any time within MAGE.";
        } else if (self.recentFetchedResultsController.fetchedObjects.count == 0 && self.otherFetchedResultsController.fetchedObjects.count == 1) {
            return @"Welcome to MAGE.  You are a part of one event.  The observations you create and your reported location will be part of this event.";
        } else if (self.recentFetchedResultsController.fetchedObjects.count == 1) {
            // they are part of one event and have seen this page before.  Should I show it?
            return @"Welcome to MAGE.  You are a part of one event.  The observations you create and your reported location will be part of this event.";
        } else if (self.recentFetchedResultsController.fetchedObjects.count > 1) {
            return @"You are part of multiple events.  The observations you create and your reported location will be part of the selected event.  You can change your event at any time within MAGE.";
        }
    }
    return nil;
}

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.filteredFetchedResultsController != nil) {
        NSString *name = [tableView.dataSource tableView:tableView titleForHeaderInSection:section];
        return [[EventTableHeaderView alloc] initWithName:name];
    }
        
    if (section == 0) return [[UIView alloc] initWithFrame:CGRectZero];
    if (section == 1 && self.recentFetchedResultsController.fetchedObjects.count == 0) return [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, CGFLOAT_MIN)];
    if (section == 2 && self.otherFetchedResultsController.fetchedObjects.count == 0) return [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, CGFLOAT_MIN)];
    
    NSString *name = [tableView.dataSource tableView:tableView titleForHeaderInSection:section];
    return [[EventTableHeaderView alloc] initWithName:name];
}

@end
