//
//  OfflineMapTableViewController.m
//  MAGE
//
//

#import "OfflineMapTableViewController.h"
#import <objc/runtime.h>
#import "CacheOverlays.h"
#import "MageConstants.h"
#import "CacheOverlayTableCell.h"
#import "ChildCacheOverlayTableCell.h"
#import "XYZDirectoryCacheOverlay.h"
#import "GeoPackageCacheOverlay.h"
#import "GPKGGeoPackageFactory.h"
#import "Theme+UIResponder.h"
#import "ObservationTableHeaderView.h"
#import "StaticLayerTableViewController.h"
#import "StaticLayerTableViewCell.h"
#import "StaticLayer.h"
#import "Layer.h"
#import "Server.h"

@interface OfflineMapTableViewController ()

@property (nonatomic, strong) NSArray *processingCaches;
@property (nonatomic, strong) CacheOverlays *cacheOverlays;
@property (nonatomic, strong) NSMutableArray<CacheOverlay *> *tableCells;
@property (nonatomic, strong) NSMutableArray<CacheOverlay *> *downloadedGeoPackageCells;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CacheOverlay *> *cacheNamesToOverlays;
@property (nonatomic, strong) NSArray *geoPackagesToDownload;
@property (nonatomic, strong) NSArray *downloadedGeoPackages;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *refreshLayersButton;
@property (nonatomic, strong) NSTimer *downloadProgressTimer;

@end

@implementation OfflineMapTableViewController

- (void) themeDidChange:(MageTheme)theme {
    self.tableView.backgroundColor = [UIColor tableBackground];
    
    [self.tableView reloadData];
}

- (instancetype) init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

-(void) viewWillAppear:(BOOL) animated {
    [super viewWillAppear:animated];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.tableView.layoutMargins = UIEdgeInsetsZero;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Refresh Layers" style:UIBarButtonItemStylePlain target:self action:@selector(refreshLayers:)];
    self.geoPackagesToDownload = [Layer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND type == %@ AND (loaded == 0 || loaded == nil)", [Server currentEventId], @"geopackage"]];
    self.downloadedGeoPackages = [Layer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND type == %@ AND loaded == 1", [Server currentEventId], @"geopackage"]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(geoPackageLayerFetched:) name: GeoPackageLayerFetched object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(geoPackageImported:) name: GeoPackageDownloaded object:nil];
    
    self.cacheOverlays = [CacheOverlays getInstance];
    [self.cacheOverlays registerListener:self];
    [self update];
    [self registerForThemeChanges];
    [self startDownloadProgressTimer];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopDownloadProgressTimer];
}

- (void) startDownloadProgressTimer {
    NSLog(@"Get timer");
    if (!_downloadProgressTimer) {
        _downloadProgressTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateDownloadProgress:) userInfo:nil repeats:YES];
    }
}

- (void) stopDownloadProgressTimer {
    if (_downloadProgressTimer) {
        [_downloadProgressTimer invalidate];
        _downloadProgressTimer = nil;
    }
}

- (void) reloadTable {
    self.geoPackagesToDownload = [Layer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND type == %@ AND (loaded == 0 || loaded == nil)", [Server currentEventId], @"geopackage"]];
    self.downloadedGeoPackages = [Layer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND type == %@ AND loaded == 1", [Server currentEventId], @"geopackage"]];
    [self.tableView reloadData];
    self.refreshLayersButton.enabled = YES;
}

- (void) geoPackageImported: (NSNotification *) notification {
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [weakSelf updateAndReloadData];
    });
}

- (void)geoPackageLayerFetched:(NSNotification *)notification {
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [weakSelf updateAndReloadData];
    });
}

- (IBAction)refreshLayers:(id)sender {
    self.refreshLayersButton.enabled = NO;
    
    [self updateAndReloadData];
    
    [Layer refreshLayersForEvent:[Server currentEventId]];
}

-(void) cacheOverlaysUpdated: (NSArray<CacheOverlay *> *) cacheOverlays{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateAndReloadData];
    });
}

-(void) updateAndReloadData{
    [self update];
    [self.tableView reloadData];
}

-(void) update{
    self.processingCaches = [self.cacheOverlays getProcessing];
    self.tableCells = [[NSMutableArray alloc] init];
    self.downloadedGeoPackageCells = [[NSMutableArray alloc] init];
    self.cacheNamesToOverlays = [[NSMutableDictionary alloc] init];
    
    self.geoPackagesToDownload = [Layer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND type == %@ AND (loaded == 0 || loaded == nil)", [Server currentEventId], @"geopackage"]];
    self.downloadedGeoPackages = [Layer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND type == %@ AND loaded == 1", [Server currentEventId], @"geopackage"]];
    self.refreshLayersButton.enabled = YES;
    
    NSMutableArray *arrayToAddTo = nil;
    for(CacheOverlay * cacheOverlay in [self.cacheOverlays getOverlays]) {
        if ([cacheOverlay isKindOfClass:[GeoPackageCacheOverlay class]]) {
            GeoPackageCacheOverlay *gpCacheOverlay = (GeoPackageCacheOverlay *)cacheOverlay;
            NSString *filePath = gpCacheOverlay.filePath;
            // check if this filePath is consistent with a downloaded layer and if so, verify that layer is in this event
            NSArray *pathComponents = [filePath pathComponents];
            if ([[pathComponents objectAtIndex:[pathComponents count] - 3] isEqualToString:@"geopackages"]) {
                NSString *layerId = [pathComponents objectAtIndex:[pathComponents count] - 2];
                // check if this layer is in the event
                NSUInteger count = [Layer MR_countOfEntitiesWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@ AND remoteId == %@", [Server currentEventId], layerId] inContext:[NSManagedObjectContext MR_defaultContext]];
                if (count != 0) {
                    arrayToAddTo = self.downloadedGeoPackageCells;
                }
            } else {
                arrayToAddTo = self.tableCells;
            }
        } else {
            arrayToAddTo = self.tableCells;
        }
        
        [arrayToAddTo addObject:cacheOverlay];
        [self.cacheNamesToOverlays setObject:cacheOverlay forKey:[cacheOverlay getCacheName]];
        if(cacheOverlay.expanded){
            for(CacheOverlay * childCacheOverlay in [cacheOverlay getChildren]){
                [arrayToAddTo addObject:childCacheOverlay];
                [self.cacheNamesToOverlays setObject:childCacheOverlay forKey:[childCacheOverlay getCacheName]];
            }
        }
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *) tableView {
    return self.processingCaches.count > 0 ? 4 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = 0;
    if (section == 0) {
        count = self.downloadedGeoPackageCells.count;
    } else if (section == 1) {
        count = self.geoPackagesToDownload.count;
    } else if (self.processingCaches.count > 0 && section == 2) {
        count = self.processingCaches.count;
    } else {
        count = [self.tableCells count];
    }
    return count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Downloaded Event Maps";
    } else if (section == 1) {
        return @"Available Maps";
    } else if (self.processingCaches.count > 0 && section == 2) {
        return @"Extracting Archives";
    } else {
        return @"Externally Loaded Maps";
    }
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 45.0f;
}

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [[ObservationTableHeaderView alloc] initWithName:[self tableView:tableView titleForHeaderInSection:section]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *cell = nil;
    
    if (indexPath.section == 0) {
        CacheOverlay * cacheOverlay = [self.downloadedGeoPackageCells objectAtIndex:[indexPath row]];
        
        UIImage * cellImage = nil;
        NSString * typeImage = [cacheOverlay getIconImageName];
        if(typeImage != nil){
            cellImage = [UIImage imageNamed:typeImage];
        }
        
        if([cacheOverlay isChild]){
            cell = [tableView dequeueReusableCellWithIdentifier:@"childCacheOverlayCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"childCacheOverlayCell"];
            }
            cell.textLabel.text = [cacheOverlay getName];
            cell.detailTextLabel.text = [cacheOverlay getInfo];
            cell.textLabel.textColor = [UIColor primaryText];
            cell.detailTextLabel.textColor = [UIColor secondaryText];
            if (cellImage != nil) {
                [cell.imageView setImage:cellImage];
                cell.imageView.tintColor = [UIColor brand];
            }
            
            CacheActiveSwitch *cacheSwitch = [[CacheActiveSwitch alloc] initWithFrame:CGRectZero];
            cacheSwitch.on = cacheOverlay.enabled;
            cacheSwitch.overlay = cacheOverlay;
            cacheSwitch.onTintColor = [UIColor themedButton];
            [cacheSwitch addTarget:self action:@selector(childActiveChanged:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = cacheSwitch;
        } else {
            cell = [tableView dequeueReusableCellWithIdentifier:@"cacheOverlayCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cacheOverlayCell"];
            }
            cell.textLabel.text = [cacheOverlay getName];
            cell.textLabel.textColor = [UIColor primaryText];
            if (cellImage != nil) {
                [cell.imageView setImage:cellImage];
                cell.imageView.tintColor = [UIColor brand];
            }
            
            CacheActiveSwitch *cacheSwitch = [[CacheActiveSwitch alloc] initWithFrame:CGRectZero];
            cacheSwitch.on = cacheOverlay.enabled;
            cacheSwitch.overlay = cacheOverlay;
            cacheSwitch.onTintColor = [UIColor themedButton];
            [cacheSwitch addTarget:self action:@selector(activeChanged:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = cacheSwitch;
        }
    } else if (indexPath.section == 1) {
        Layer *layer = [self geoPackageForRow:indexPath.row];

        cell = [tableView dequeueReusableCellWithIdentifier:@"staticLayerCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"staticLayerCell"];
        }
        
        cell.textLabel.text = layer.name;
        cell.textLabel.textColor = [UIColor primaryText];
        cell.detailTextLabel.textColor = [UIColor secondaryText];
        cell.backgroundColor = [UIColor background];

        if (!layer.downloading) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", [NSByteCountFormatter stringFromByteCount:[[[layer file] valueForKey:@"size"] intValue] countStyle:NSByteCountFormatterCountStyleFile]];
            UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"download_thumbnail"]];
            imageView.frame = CGRectMake(0, 0, 30, 30);
            imageView.layer.cornerRadius = 15.0f;
            imageView.layer.masksToBounds = YES;
            cell.accessoryView = imageView;
        } else {
            uint64_t downloadBytes = [layer.downloadedBytes longLongValue];
            NSLog(@"Download bytes %ld", (long)downloadBytes);
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Downloading, Please wait: %@ of %@",
                                         [NSByteCountFormatter stringFromByteCount:downloadBytes countStyle:NSByteCountFormatterCountStyleFile],
                                         [NSByteCountFormatter stringFromByteCount:[[[layer file] valueForKey:@"size"] intValue] countStyle:NSByteCountFormatterCountStyleFile]];

            UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [activityIndicator setFrame:CGRectZero];
            [activityIndicator startAnimating];
            activityIndicator.color = [UIColor secondaryText];
            cell.accessoryView = activityIndicator;
        }
    } else if (self.processingCaches.count > 0 && [indexPath section] == 2) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"processingOfflineMapCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"processingOfflineMapCell"];
        }
        cell.textLabel.text = [self.processingCaches objectAtIndex:[indexPath row]];
        cell.textLabel.textColor = [UIColor primaryText];
        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [activityIndicator setFrame:CGRectZero];
        [activityIndicator startAnimating];
        activityIndicator.color = [UIColor secondaryText];
        cell.accessoryView = activityIndicator;
    } else {
        CacheOverlay * cacheOverlay = [self.tableCells objectAtIndex:[indexPath row]];
        
        UIImage * cellImage = nil;
        NSString * typeImage = [cacheOverlay getIconImageName];
        if(typeImage != nil){
            cellImage = [UIImage imageNamed:typeImage];
        }
        
        if([cacheOverlay isChild]){
            cell = [tableView dequeueReusableCellWithIdentifier:@"childCacheOverlayCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"childCacheOverlayCell"];
            }
            cell.textLabel.text = [cacheOverlay getName];
            cell.detailTextLabel.text = [cacheOverlay getInfo];
            cell.textLabel.textColor = [UIColor primaryText];
            cell.detailTextLabel.textColor = [UIColor secondaryText];
            if (cellImage != nil) {
                [cell.imageView setImage:cellImage];
                cell.imageView.tintColor = [UIColor brand];
            }
            
            CacheActiveSwitch *cacheSwitch = [[CacheActiveSwitch alloc] initWithFrame:CGRectZero];
            cacheSwitch.on = cacheOverlay.enabled;
            cacheSwitch.overlay = cacheOverlay;
            cacheSwitch.onTintColor = [UIColor themedButton];
            [cacheSwitch addTarget:self action:@selector(childActiveChanged:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = cacheSwitch;
        } else {
            cell = [tableView dequeueReusableCellWithIdentifier:@"cacheOverlayCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cacheOverlayCell"];
            }
            cell.textLabel.text = [cacheOverlay getName];
            cell.textLabel.textColor = [UIColor primaryText];
            if (cellImage != nil) {
                [cell.imageView setImage:cellImage];
                cell.imageView.tintColor = [UIColor brand];
            }
            
            CacheActiveSwitch *cacheSwitch = [[CacheActiveSwitch alloc] initWithFrame:CGRectZero];
            cacheSwitch.on = cacheOverlay.enabled;
            cacheSwitch.overlay = cacheOverlay;
            cacheSwitch.onTintColor = [UIColor themedButton];
            [cacheSwitch addTarget:self action:@selector(activeChanged:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = cacheSwitch;
        }
    }
    
    cell.backgroundColor = [UIColor background];
    return cell;
}

- (void) updateDownloadProgress: (NSTimer *) timer {
    NSIndexSet *section = [NSIndexSet indexSetWithIndex:1];
    [self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationNone];
}

- (Layer *) geoPackageForRow: (NSUInteger) row {
    return [self.geoPackagesToDownload objectAtIndex: row];
}

- (Layer *) downloadedGeoPackageForRow: (NSUInteger) row {
    return [self.downloadedGeoPackages objectAtIndex: row];
}

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
    if (indexPath.section == 0) {
        // add the geopackage to the map
        CacheOverlay * cacheOverlay = [self.downloadedGeoPackageCells objectAtIndex:[indexPath row]];
        if([cacheOverlay getSupportsChildren]){
            [cacheOverlay setExpanded:!cacheOverlay.expanded];
            [self updateAndReloadData];
        }
    } else if (indexPath.section == 1) {
        [tableView deselectRowAtIndexPath:[tableView indexPathForSelectedRow] animated:NO];
        
        UITableViewCell *cell =  [tableView cellForRowAtIndexPath:indexPath];
        Layer *geopackageLayer = [self geoPackageForRow:indexPath.row];
        // kick off the download
        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [activityIndicator setFrame:CGRectZero];
        [activityIndicator startAnimating];
        activityIndicator.color = [UIColor secondaryText];
        cell.accessoryView = activityIndicator;
        [self.tableView reloadData];
        
        __weak typeof(self) weakSelf = self;

        [MagicalRecord saveWithBlock:^(NSManagedObjectContext * _Nonnull localContext) {
            Layer *localLayer = [geopackageLayer MR_inContext:localContext];
            
            localLayer.downloading = YES;
            localLayer.downloadedBytes = 0;
        } completion:^(BOOL contextDidSave, NSError * _Nullable error) {
            [Layer downloadGeoPackage:geopackageLayer success:^{
            } failure:^(NSError * _Nonnull error) {
            }];
            
            [weakSelf updateAndReloadData];
        }];
        
    } else if (self.processingCaches.count == 0 || [indexPath section] == 2){
        CacheOverlay * cacheOverlay = [self.tableCells objectAtIndex:[indexPath row]];
        if([cacheOverlay getSupportsChildren]){
            [cacheOverlay setExpanded:!cacheOverlay.expanded];
            [self updateAndReloadData];
        }
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (IBAction)activeChanged:(CacheActiveSwitch *)sender {
    
    CacheOverlay * cacheOverlay = sender.overlay;
    
    [cacheOverlay setEnabled:sender.on];
    
    BOOL modified = false;
    for(CacheOverlay * childCache in [cacheOverlay getChildren]){
        if(childCache.enabled != cacheOverlay.enabled){
            [childCache setEnabled:cacheOverlay.enabled];
            modified = true;
        }
    }
    
    if(modified){
        [self.tableView reloadData];
    }
    
    [self updateSelectedAndNotify];
}

- (IBAction)childActiveChanged:(CacheActiveSwitch *)sender {
    
    CacheOverlay * cacheOverlay = sender.overlay;
    CacheOverlay * parentOverlay = [cacheOverlay getParent];
    
    [cacheOverlay setEnabled:sender.on];
    
    BOOL parentEnabled = true;
    if(!cacheOverlay.enabled){
        parentEnabled = false;
        for(CacheOverlay * childOverlay in [parentOverlay getChildren]){
            if(childOverlay.enabled){
                parentEnabled = true;
                break;
            }
        }
    }
    if(parentEnabled != parentOverlay.enabled){
        [parentOverlay setEnabled:parentEnabled];
        [self.tableView reloadData];
    }
    
    [self updateSelectedAndNotify];
}

-(void) updateSelectedAndNotify{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[self getSelectedOverlays] forKey:MAGE_SELECTED_CACHES];
    [defaults synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.cacheOverlays notifyListenersExceptCaller:self];
    });
}

-(NSArray *) getSelectedOverlays{
    NSMutableArray * overlays = [[NSMutableArray alloc] init];
    for(CacheOverlay * cacheOverlay in [self.cacheOverlays getOverlays]){
        
        BOOL childAdded = false;
        for(CacheOverlay * childCache in [cacheOverlay getChildren]){
            if(childCache.enabled){
                [overlays addObject:[childCache getCacheName]];
                childAdded = true;
            }
        }
        
        if(!childAdded && cacheOverlay.enabled){
            [overlays addObject:[cacheOverlay getCacheName]];
        }
    }
    return overlays;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCellEditingStyle style = UITableViewCellEditingStyleNone;

    if([indexPath section] == 0){
        CacheOverlay * cacheOverlay = [self.downloadedGeoPackageCells objectAtIndex:[indexPath row]];
        if(![cacheOverlay isChild]){
            style = UITableViewCellEditingStyleDelete;
        }
    } else if ([indexPath section] == 1) {
        CacheOverlay * cacheOverlay = [self.tableCells objectAtIndex:[indexPath row]];
        if(![cacheOverlay isChild]){
            style = UITableViewCellEditingStyleDelete;
        }
    }

    return style;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;

    // If row is deleted, remove it from the list.
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (indexPath.section == 0) {
            GeoPackageCacheOverlay *cacheOverlay = (GeoPackageCacheOverlay *)[self.downloadedGeoPackageCells objectAtIndex:[indexPath row]];
            [MagicalRecord saveWithBlock:^(NSManagedObjectContext * _Nonnull localContext) {
                NSString *filePath = cacheOverlay.filePath;
                NSArray *pathComponents = [filePath pathComponents];
                NSString *layerId = [pathComponents objectAtIndex:[pathComponents count] - 2];
                Layer *layer = [Layer MR_findFirstWithPredicate:[NSPredicate predicateWithFormat:@"remoteId == %@", layerId] inContext:localContext];
                layer.loaded = [NSNumber numberWithBool:NO];
            } completion:^(BOOL contextDidSave, NSError * _Nullable error) {
                [weakSelf deleteCacheOverlay:cacheOverlay];
                [weakSelf updateAndReloadData];
            }];
        } else if (indexPath.section == 3) {
            CacheOverlay * cacheOverlay = [self.tableCells objectAtIndex:[indexPath row]];
            [self deleteCacheOverlay:cacheOverlay];
        }
    }
}

-(void)deleteCacheOverlay: (CacheOverlay *) cacheOverlay{
    switch([cacheOverlay getType]){
        case XYZ_DIRECTORY:
            [self deleteXYZCacheOverlay:(XYZDirectoryCacheOverlay *)cacheOverlay];
            break;
        case GEOPACKAGE:
            [self deleteGeoPackageCacheOverlay:(GeoPackageCacheOverlay *)cacheOverlay];
            break;
        default:
            
            break;
    }
    [self.cacheOverlays removeCacheOverlay:cacheOverlay];
}

-(void) deleteXYZCacheOverlay: (XYZDirectoryCacheOverlay *) xyzCacheOverlay{
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[xyzCacheOverlay getDirectory] error:&error];
    if(error){
        NSLog(@"Error deleting XYZ cache directory: %@. Error: %@", [xyzCacheOverlay getDirectory], error);
    }
}

-(void) deleteGeoPackageCacheOverlay: (GeoPackageCacheOverlay *) geoPackageCacheOverlay{
    
    GPKGGeoPackageManager * manager = [GPKGGeoPackageFactory getManager];
    if(![manager delete:[geoPackageCacheOverlay getName]]){
        NSLog(@"Error deleting GeoPackage cache file: %@", [geoPackageCacheOverlay getName]);
    }
}

@end
