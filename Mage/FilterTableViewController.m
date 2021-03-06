//
//  FilterTableViewController.m
//  MAGE
//
//  Created by Dan Barela on 7/20/17.
//  Copyright © 2017 National Geospatial Intelligence Agency. All rights reserved.
//

#import "FilterTableViewController.h"
#import "Filter.h"
#import "Theme+UIResponder.h"

@interface FilterTableViewController ()
@property (assign, nonatomic) BOOL isPopover;
@end

@implementation FilterTableViewController

- (void) themeDidChange:(MageTheme)theme {
    self.view.backgroundColor = [UIColor background];
    self.tableView.backgroundColor = [UIColor tableBackground];
    self.navigationController.navigationBar.barTintColor = [UIColor primary];
    [self.tableView reloadData];
}

- (void) viewDidLoad {
    [super viewDidLoad];
    [self setPreferredContentSize:CGSizeMake(340.0f, 550.0f)];
    [self registerForThemeChanges];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.tableView reloadData];
}

- (IBAction)backButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    NSString *filterString = @"";
    if ([indexPath row] == 0) {
        filterString = [Filter getFilterString];
        if ([filterString length] == 0) {
            filterString = @"All";
        }
    } else if ([indexPath row] == 1) {
        filterString = [Filter getLocationFilterString];
        if ([filterString length] == 0) {
            filterString = @"All";
        }
    }
    
    cell.detailTextLabel.text = filterString;
    
    cell.backgroundColor = [UIColor background];
    cell.detailTextLabel.textColor = [UIColor secondaryText];
    cell.textLabel.textColor = [UIColor primaryText];
    
    return cell;
}

- (void)tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

@end
