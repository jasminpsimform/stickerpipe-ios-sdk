//
// Created by vlad on 7/27/16.
// Copyright (c) 2016 908 Inc. All rights reserved.
//

#import "STKWebserviceManager.h"
#import "AFHTTPSessionManager.h"
#import "STKStickersManager.h"
#import "STKUUIDManager.h"
#import "STKApiKeyManager.h"
#import "STKStickersConstants.h"
#import "STKSearchModel.h"
#import "STKUtility.h"
#import "STKStatistic.h"


@interface STKWebserviceManager ()
@property (nonatomic, readonly) AFHTTPSessionManager* getSessionManager;
@property (nonatomic, readonly) AFHTTPSessionManager* stickerSessionManager;
@property (nonatomic, readonly) AFHTTPSessionManager* sessionManager;

//
// moved from old code;
// same as sessionManager, but with content type set
@property (nonatomic, readonly) AFHTTPSessionManager* analyticSessionManager;
// same as sessionManager, but with completion run on the background queue
@property (nonatomic, readonly) AFHTTPSessionManager* backgroundSessionManager;
//

@property (nonatomic) BOOL networkReachable;

@property (nonatomic, readonly) NSString* rootURLString;
@end

@implementation STKWebserviceManager

static STKConstStringKey kPacksURL = @"shop/my";
static STKConstStringKey kStatisticUrl = @"statistics";
static STKConstStringKey kSearchURL = @"search";
static STKConstStringKey kSTKApiVersion = @"v2";

+ (instancetype)sharedInstance {
	static STKWebserviceManager* sharedInstance = nil;

	@synchronized (self){
		if (!sharedInstance) {
			sharedInstance = [STKWebserviceManager new];
		}
	}

	return sharedInstance;
}

- (instancetype)init {
	if (self = [super init]) {
		static const BOOL work = !YES;
		_rootURLString = work ? @"http://work.stk.908.vc/" : @"https://api.stickerpipe.com/";

		NSURL* URL = [NSURL URLWithString: [NSString stringWithFormat: @"%@/api/%@", self.rootURLString, kSTKApiVersion]];

		NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
		config.HTTPMaximumConnectionsPerHost = 1;
		config.timeoutIntervalForRequest = 180;

		_stickerSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL: URL sessionConfiguration: config];
		_sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL: URL];
		_getSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL: URL];

		self.stickerSessionManager.requestSerializer = [self baseSerializer];
		self.sessionManager.requestSerializer = [self baseSerializer];
		self.getSessionManager.requestSerializer = [self getSerializer];

		_analyticSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL: URL];
		self.analyticSessionManager.requestSerializer = [self baseSerializer];
		[self.analyticSessionManager.requestSerializer setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];

		_backgroundSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL: URL];
		self.backgroundSessionManager.requestSerializer = [self baseSerializer];
		self.backgroundSessionManager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	}

	return self;
}

- (AFJSONRequestSerializer*)baseSerializer {
	AFJSONRequestSerializer* serializer = [AFJSONRequestSerializer serializer];
	[serializer setValue: [STKStickersManager userKey] forHTTPHeaderField: @"UserID"];
	[serializer setValue: kSTKApiVersion forHTTPHeaderField: @"ApiVersion"];
	[serializer setValue: @"iOS" forHTTPHeaderField: @"Platform"];
	[serializer setValue: [STKUUIDManager generatedDeviceToken] forHTTPHeaderField: @"DeviceId"];
	[serializer setValue: [STKApiKeyManager apiKey] forHTTPHeaderField: @"ApiKey"];
	[serializer setValue: [[NSBundle mainBundle] bundleIdentifier] forHTTPHeaderField: @"Package"];
	[serializer setValue: [self localization] forHTTPHeaderField: @"Localization"];

	return serializer;
}

- (AFJSONRequestSerializer*)getSerializer {
	AFJSONRequestSerializer* serializer = [self baseSerializer];
	NSNumber* isSubscriber = @([STKStickersManager isSubscriber]);
	[serializer setValue: [isSubscriber stringValue] forHTTPHeaderField: @"is_subscriber"];

	return serializer;
}

- (NSString*)localization {
	return [[NSUserDefaults standardUserDefaults] stringForKey: kLocalizationDefaultsKey] ?:
			[NSLocale preferredLanguages][0];
}

- (void)searchStickersWithSearchModel: (STKSearchModel*)searchModel completion: (void (^)(NSArray* stickers))completion {
	if (searchModel.isSuggest) {
		searchModel.topIfEmpty = @"0";
		searchModel.wholeWord = @"1";
	} else {
		searchModel.topIfEmpty = @"1";
		searchModel.wholeWord = @"0";
	}

	searchModel.limit = @"20";

	NSDictionary* params = @{
			@"q" : searchModel.q,
			@"top_if_empty" : searchModel.topIfEmpty,
			@"whole_word" : searchModel.wholeWord,
			@"limit" : searchModel.limit
	};

	[[STKWebserviceManager sharedInstance].getSessionManager GET: kSearchURL parameters: params success: ^ (NSURLSessionDataTask* task, id responseObject) {
		if (completion) {
			completion(responseObject[@"data"]);
		}
	}                   failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (completion) {
			completion(nil);
		}
	}];
}

- (void)loadStickerPackWithName: (NSString*)packName andPricePoint: (NSString*)pricePoint
						success: (void (^)(id))success
						failure: (void (^)(NSError*))failure {
	NSString* route = [NSString stringWithFormat: @"packs/%@", packName];
	NSDictionary* params = @{@"purchase_type" : [self purchaseType: pricePoint]};

	[[STKWebserviceManager sharedInstance].stickerSessionManager POST: route parameters: params success: ^ (NSURLSessionDataTask* task, id responseObject) {
		if (success) {
			success(responseObject);
		}
	}                        failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (failure) {
			failure(error);
		}
	}];
}

- (void)getStickersPacksForUserWithSuccess: (void (^)(id response, NSTimeInterval lastModifiedDate))success
								   failure: (void (^)(NSError* error))failure {
	NSDictionary* params = @{@"is_subscriber" : @([STKStickersManager isSubscriber])};

	[[STKWebserviceManager sharedInstance].getSessionManager GET: kPacksURL parameters: params success: ^ (NSURLSessionDataTask* task, id responseObject) {
		NSTimeInterval timeInterval = 0;

		timeInterval = [responseObject[@"meta"][@"shop_last_modified"] doubleValue];

		if ([responseObject[@"data"] count] == 0) {
			STKLog(@"get empty stickers pack JSON");
		}

		if (success) {
			success(responseObject, timeInterval);
		}
	}                   failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (failure) {
			dispatch_async(dispatch_get_main_queue(), ^ {
				failure(error);
			});
		}
	}];
}

- (void)sendStatistics: (NSArray*)statisticsArray success: (void (^)(id))success failure: (void (^)(NSError*))failure {
	NSMutableArray* array = [NSMutableArray array];

	for (STKStatistic* statistic in statisticsArray) {
		[array addObject: [statistic dictionary]];
	}

	if (array.count > 0) {
		[self.analyticSessionManager POST: kStatisticUrl parameters: array success: ^ (NSURLSessionDataTask* task, id responseObject) {
			if (success) {
				success(responseObject);
			}
		}                 failure: ^ (NSURLSessionDataTask* task, NSError* error) {
			if (failure) {
				failure(error);
			}
		}];
	}
}

- (NSString*)purchaseType: (NSString*)pricePoint {
	if ([pricePoint isEqualToString: @"A"]) {
		return @"free";
	} else if ([pricePoint isEqualToString: @"B"]) {
		return [STKStickersManager isSubscriber] ? @"subscription" : @"oneoff";
	} else if ([pricePoint isEqualToString: @"C"]) {
		return @"oneoff";
	}
	return @"";
}

- (void)getStickerInfoWithId: (NSString*)contentId
					 success: (void (^)(id response))success
					 failure: (void (^)(NSError*))failure {
	NSString* route = [NSString stringWithFormat: @"content/%@", contentId];

	[self.backgroundSessionManager GET: route parameters: nil success: ^ (NSURLSessionDataTask* task, id responseObject) {
		if (success) {
			success(responseObject);
		}
	}                failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (failure) {
			failure(error);
		}
	}];
}

- (void)getStickersPackWithType: (NSString*)type
						success: (void (^)(id response, NSTimeInterval lastModifiedDate))success
						failure: (void (^)(NSError* error))failure {

	NSDictionary* parameters = nil;
	if (type) {
		parameters = @{@"type" : type};
	}

	[self.backgroundSessionManager GET: kPacksURL parameters: parameters success: ^ (NSURLSessionDataTask* task, id responseObject) {
		NSHTTPURLResponse* response = ((NSHTTPURLResponse*) [task response]);
		NSTimeInterval timeInterval = 0;
		if ([response respondsToSelector: @selector(allHeaderFields)]) {
			NSDictionary* headers = [response allHeaderFields];
			timeInterval = [headers[@"Last-Modified"] doubleValue];
		}

		if ([responseObject[@"data"] count] == 0) {
			STKLog(@"get empty stickers pack JSON");
		}

		if (success) {
			success(responseObject, timeInterval);
		}
	}                failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (failure) {
			dispatch_async(dispatch_get_main_queue(), ^ {
				failure(error);
			});
		}
	}];
}

- (void)getStickerPackWithName: (NSString*)packName
					   success: (void (^)(id))success
					   failure: (void (^)(NSError*))failure {
	NSString* route = [NSString stringWithFormat: @"pack/%@", packName];

	[self.backgroundSessionManager GET: route parameters: nil success: ^ (NSURLSessionDataTask* task, id responseObject) {
		if (success) {
			success(responseObject);
		}
	}                failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (failure) {
			failure(error);
		}
	}];
}

- (void)deleteStickerPackWithName: (NSString*)packName
						  success: (void (^)(id))success
						  failure: (void (^)(NSError*))failure {
	NSString* route = [NSString stringWithFormat: @"packs/%@", packName];

	[self.backgroundSessionManager DELETE: route parameters: nil success: ^ (NSURLSessionDataTask* task, id responseObject) {
		if (success) {
			success(responseObject);
		}
	}                   failure: ^ (NSURLSessionDataTask* task, NSError* error) {
		if (failure) {
			failure(error);
		}
	}];
}

- (void)sendDeviceToken: (NSString*)token failure: (void (^)(NSError*))failure {
	[self.backgroundSessionManager POST: @"token" parameters: @{@"token" : token} success: nil failure: ^ (NSURLSessionDataTask* _Nullable task, NSError* _Nonnull error) {
		if (failure) {
			failure(error);
		}
	}];
}


#pragma mark - Reachability

- (void)startCheckingNetwork {
	static dispatch_once_t once;
	dispatch_once(&once, ^ {
		[[AFNetworkReachabilityManager sharedManager] startMonitoring];

		[[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock: ^ (AFNetworkReachabilityStatus status) {
			self.networkReachable = (status == AFNetworkReachabilityStatusReachableViaWWAN ||
					status == AFNetworkReachabilityStatusReachableViaWiFi);
		}];
	});
}


#pragma mark -

- (NSString* )stickerUrl
{
	NSString* lang = [[NSLocale preferredLanguages] objectAtIndex: 0];

	NSString* language = [[lang componentsSeparatedByString: @"-"] objectAtIndex: 0];

	NSString* color = [[NSUserDefaults standardUserDefaults] stringForKey: kShopColor];
	if (color == nil || [color isEqualToString: @""]) {
		color = @"047aff";
	}

	/**
	 *  Shop content color from navigation controller

	 UIColor *navigationBarColor = self.navigationController.navigationBar.backgroundColor;

	 CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha =0.0;
	 [navigationBarColor getRed:&red green:&green blue:&blue alpha:&alpha];

	 int r,g,b,a;

	 r = (int)(255.0 * red);
	 g = (int)(255.0 * green);
	 b = (int)(255.0 * blue);
	 a = (int)(255.0 * alpha);

	 NSString *color = [NSString stringWithFormat:@"%02x%02x%02x", r, g, b];
	 */

	return [NSMutableString stringWithFormat: @"%@api/v2/web?&apiKey=%@&platform=IOS&userId=%@&density=%@&is_subscriber=%d&primaryColor=%@&localization=%@", self.rootURLString, [STKApiKeyManager apiKey], [STKStickersManager userKey], [STKUtility scaleString], [STKStickersManager isSubscriber], color, language];
}


#pragma mark - URL

- (NSURL*)stkUrl {
	return [NSURL URLWithString: [NSString stringWithFormat: @"%@stk/", self.rootURLString]];
}

- (NSURL*)imageUrlForStickerMessage: (NSString*)stickerMessage andDensity: (NSString*)density {
	NSArray* separatedStickerNames = [STKUtility trimmedPackNameAndStickerNameWithMessage: stickerMessage];
	NSString* packName = [[separatedStickerNames firstObject] lowercaseString];
	NSString* stickerName = [[separatedStickerNames lastObject] lowercaseString];

	NSString* urlString = [NSString stringWithFormat: @"%@/%@_%@.png", packName, stickerName, density];

	return [NSURL URLWithString: urlString relativeToURL: [self stkUrl]];
}

- (NSURL*)tabImageUrlForPackName: (NSString*)name {
	NSString* density = [STKUtility scaleString];

	NSString* urlString = [NSString stringWithFormat: @"%@/tab_icon_%@.png", name, density];

	return [NSURL URLWithString: urlString relativeToURL: [self stkUrl]];
}

- (NSURL*)mainImageUrlForPackName: (NSString*)name {
	NSString* density = [STKUtility scaleString];

	NSString* urlString = [NSString stringWithFormat: @"%@/main_icon_%@.png", name, density];

	return [NSURL URLWithString: urlString relativeToURL: [self stkUrl]];
}

- (NSURL*)imageUrlForStickerPanelWithMessage: (NSString*)stickerMessage {
	NSArray* separatedStickerNames = [STKUtility trimmedPackNameAndStickerNameWithMessage: stickerMessage];
	NSString* packName = [[separatedStickerNames firstObject] lowercaseString];
	NSString* stickerName = [[separatedStickerNames lastObject] lowercaseString];
	NSString* urlString = [NSString stringWithFormat: @"%@/%@_mdpi.png", packName, stickerName];

	return [NSURL URLWithString: urlString relativeToURL: [self stkUrl]];
}

@end