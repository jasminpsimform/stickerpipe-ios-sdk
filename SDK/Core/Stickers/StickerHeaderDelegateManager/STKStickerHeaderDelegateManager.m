//
//  STKStickerHeaderDelegateManager.m
//  StickerPipe
//
//  Created by Vadim Degterev on 21.07.15.
//  Copyright (c) 2015 908 Inc. All rights reserved.
//

#import "STKStickerHeaderDelegateManager.h"
#import "STKStickerHeaderCell.h"
#import "STKStickerPackObject.h"


@implementation STKStickerHeaderDelegateManager

#pragma mark - UICollectionViewDelegate

- (NSInteger)numberOfSectionsInCollectionView: (UICollectionView*)collectionView {
	return self.stickerPacksArray.count > 0 ? 1 : 0;
}

- (NSInteger)collectionView: (UICollectionView*)collectionView numberOfItemsInSection: (NSInteger)section {
    return self.stickerPacksArray.count;
}

- (UICollectionViewCell*)collectionView: (UICollectionView*)collectionView cellForItemAtIndexPath: (NSIndexPath*)indexPath {
	STKStickerHeaderCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier: @"STKStickerPanelHeaderCell" forIndexPath: indexPath];

	cell.layer.shouldRasterize = YES;
	cell.layer.rasterizationScale = [UIScreen mainScreen].scale;

	if (indexPath.section == 0 && self.stickerPacksArray.count > 0) {
		STKStickerPackObject* stickerPack = self.stickerPacksArray[(NSUInteger) indexPath.item];

		[cell configWithStickerPack: stickerPack placeholder: self.placeholderImage placeholderTintColor: self.placeholderHeaderColor collectionView: collectionView cellForItemAtIndexPath: indexPath];
	} else {
		[cell configureSettingsCell];
	}

	return cell;
}


#pragma mark - UICollectionViewDelegate

- (void)collectionView: (UICollectionView*)collectionView didSelectItemAtIndexPath: (NSIndexPath*)indexPath {
	if (indexPath.section == 0 && self.stickerPacksArray.count > 0) {
		self.didSelectRow(indexPath, self.stickerPacksArray[(NSUInteger) indexPath.item], YES);
	} else {
		self.didSelectSettingsRow();
	}
}

- (void)scrollToIndexPath: (NSIndexPath*)indexPath animated: (BOOL)animated {
	if (indexPath.section == 0 && self.stickerPacksArray.count > 0) {
		self.didSelectRow(indexPath, self.stickerPacksArray[(NSUInteger) indexPath.item], animated);
	} else {
		self.didSelectSettingsRow();
	}
}


@end
