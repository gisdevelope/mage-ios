//
//  AttachmentEditTableViewCell.m
//  MAGE
//
//  Created by Dan Barela on 12/1/14.
//  Copyright (c) 2014 National Geospatial Intelligence Agency. All rights reserved.
//

#import "AttachmentEditTableViewCell.h"
#import "AttachmentCollectionDataStore.h"

@interface AttachmentEditTableViewCell ()

@property (strong, nonatomic) AttachmentCollectionDataStore *ads;
@property (weak, nonatomic) IBOutlet UICollectionView *attachmentCollection;

@end

@implementation AttachmentEditTableViewCell

- (void) populateCellWithFormField: (id) field andObservation: (Observation *) observation {
    if (self.ads == nil) {
        self.ads = [[AttachmentCollectionDataStore alloc] init];
        self.ads.attachmentCollection = self.attachmentCollection;
        self.attachmentCollection.delegate = self.ads;
        self.attachmentCollection.dataSource = self.ads;
        self.ads.observation = observation;
    } else {
        [self.ads.attachmentCollection reloadData];
    }
//    self.ads.attachmentSelectionDelegate = self.attachmentSelectionDelegate;
}

- (CGFloat) getCellHeightForValue: (id) value {
    if (value == [NSNumber numberWithInt:0]) {
        return 0.0;
    }
    return self.bounds.size.height;
}

@end
