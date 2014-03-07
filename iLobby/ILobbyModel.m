//
//  ILobbyModel.m
//  iLobby
//
//  Created by Pelaia II, Tom on 10/23/12.
//  Copyright (c) 2012 UT-Battelle ORNL. All rights reserved.
//

#import "ILobbyModel.h"
#import "ILobbyPresentationDownloader.h"
#import "ILobbyStoreUserConfig.h"
#import "ILobbyStorePresentation.h"
#import "ILobbyRemoteDirectory.h"


@interface ILobbyModel ()
@property (strong, nonatomic) ILobbyStoreUserConfig *userConfig;
@property (strong, nonatomic) ILobbyPresentationDownloader *presentationDownloader;
@property (strong, readwrite) ILobbyProgress *downloadProgress;
@property (readwrite) BOOL hasPresentationUpdate;
@property (readwrite) BOOL playing;
@property (strong, readwrite) NSArray *tracks;
@property (strong, readwrite) ILobbyTrack *defaultTrack;
@property (strong, readwrite) ILobbyTrack *currentTrack;

// managed object support
@property (nonatomic, readwrite) NSManagedObjectContext *managedObjectContext;
@end


@implementation ILobbyModel

// class initializer
+(void)initialize {
	if ( self == [ILobbyModel class] ) {
		[self purgeVersion1Data];
	}
}


// purge version 1.x data
+(void)purgeVersion1Data {
	NSString *oldPresentationPath = [[self.documentDirectoryURL path] stringByAppendingPathComponent:@"Presentation"];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ( [fileManager fileExistsAtPath:oldPresentationPath] ) {
		NSError * __autoreleasing error;
		[fileManager removeItemAtPath:oldPresentationPath error:&error];
		if ( error ) {
			NSLog( @"Error removing version 1.0 presentation directory." );
		}
	}
}


+ (NSURL *)documentDirectoryURL {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError * __autoreleasing error;

	NSURL *documentDirectoryURL = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
	if ( error ) {
		NSLog( @"Error getting to document directory: %@", error );
		return nil;
	}
	else {
		return documentDirectoryURL;
	}
}


- (id)init {
    self = [super init];
    if (self) {
		self.playing = NO;
		
		self.downloadProgress = [ILobbyProgress progressWithFraction:0.0f label:@""];
		[self setupDataModel];

		self.userConfig = [self fetchUserConfig];
		[self loadDefaultPresentation];
    }
    return self;
}


- (void)setupDataModel {
	// load the managed object model from the main bundle
    NSManagedObjectModel *managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];

	// setup the persistent store
    NSURL *storeUrl = [NSURL fileURLWithPath: [[self applicationDocumentsDirectory] stringByAppendingPathComponent: @"iLobby.db"]];

	NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };

    NSError * __autoreleasing error = nil;
    NSPersistentStoreCoordinator *persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    if ( ![persistentStoreCoordinator addPersistentStoreWithType:NSBinaryStoreType configuration:nil URL:storeUrl options:options error:&error] ) {
        /*
         TODO: Replace this implementation with code to handle the error appropriately.

         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. If it is not possible to recover from the error, display an alert panel that instructs the user to quit the application by pressing the Home button.

         Typical reasons for an error here include:
         * The persistent store is not accessible
         * The schema for the persistent store is incompatible with current managed object model
         Check the error message to determine what the actual problem was.
         */
        NSLog( @"Unresolved error %@, %@", error, [error userInfo] );
        abort();
    }

	// setup the managed object context
    if ( persistentStoreCoordinator != nil ) {
        self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
		self.managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator;
    }
}


/** Returns the path to the application's Documents directory. */
- (NSString *)applicationDocumentsDirectory {
    return [NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES ) lastObject];
}


- (NSManagedObjectModel *)managedObjectModel {
	return self.persistentStoreCoordinator.managedObjectModel;
}


- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
	return self.managedObjectContext.persistentStoreCoordinator;
}


- (void)setPresentationDelegate:(id<ILobbyPresentationDelegate>)presentationDelegate {
	_presentationDelegate = presentationDelegate;
}


- (BOOL)canPlay {
	NSArray *tracks = self.tracks;
	return tracks != nil && tracks.count > 0;
}


- (BOOL)play {
	if ( [self canPlay] ) {
		[self playTrack:self.defaultTrack cancelCurrent:YES];
		self.playing = YES;
		return YES;
	}
	else {
		return NO;
	}
}


- (void)stop {
	self.playing = NO;
	[self.currentTrack cancelPresentation];
}


- (void)performShutdown {
	// stop the presentation
	[self stop];

	// check to see if there are any pending installations to install
	if ( self.hasPresentationUpdate ) {
		[self installPresentation];
		[self loadDefaultPresentation];
	}
}


- (void)playTrackAtIndex:(NSUInteger)trackIndex {
//	NSLog( @"Play track at index: %d", trackIndex );
	ILobbyTrack *track = self.tracks[trackIndex];
	[self playTrack:track cancelCurrent:YES];
}


- (void)playTrack:(ILobbyTrack *)track cancelCurrent:(BOOL)cancelCurrent {
	ILobbyTrack *oldTrack = self.currentTrack;
	if ( cancelCurrent && oldTrack )  [oldTrack cancelPresentation];

	id<ILobbyPresentationDelegate> presentationDelegate = self.presentationDelegate;
	if ( presentationDelegate ) {
		self.currentTrack = track;
		[track presentTo:presentationDelegate completionHandler:^(ILobbyTrack *track) {
			// if playing, present the default track after any track completes on its own (no need to cancel)
			if ( self.playing ) {
				// check whether a new presentation download is ready and install and load it if so
				if ( self.hasPresentationUpdate ) {
					[self stop];
					[self installPresentation];
					[self loadDefaultPresentation];
					[self play];
				}
				else {
					// play the default track
					[self playTrack:self.defaultTrack cancelCurrent:NO];
				}
			}
		}];
	}
}


- (BOOL)validateDownload:(NSError **)error {
//	NSFileManager *fileManager = [NSFileManager defaultManager];
//	NSString *downloadPath = [ILobbyPresentationDownloader presentationPath];
//
//	if ( [fileManager fileExistsAtPath:downloadPath] ) {
//		NSString *indexPath = [downloadPath stringByAppendingPathComponent:@"index.json"];
//		if ( [fileManager fileExistsAtPath:indexPath] ) {
//			NSError *jsonError;
//			NSData *indexData = [NSData dataWithContentsOfFile:indexPath];
//			[NSJSONSerialization JSONObjectWithData:indexData options:0 error:&jsonError];
//			if ( jsonError ) {
//				if ( error ) {
//					*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:1 userInfo:@{ @"message" : @"Main index File is corrupted" }];
//				}
//				return NO;
//			}
//			else {
//				return YES;
//			}
//		}
//		else {
//			if ( error ) {
//				*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:1 userInfo:@{ @"message" : @"Main index File Missing" }];
//			}
//			return NO;
//		}
//	}
//	else {
//		if ( error ) {
//			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:1 userInfo:@{ @"message" : @"Download Directory Missing" }];
//		}
//		return NO;
//	}
	return YES;
}


- (void)installPresentation {
	// TODO: implement installation logic
	self.hasPresentationUpdate = NO;
}


- (ILobbyStoreUserConfig *)fetchUserConfig {
	NSFetchRequest *mainFetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"UserConfig"];

	ILobbyStoreUserConfig *userConfig = nil;
	NSError * __autoreleasing error = nil;
	NSArray *userConfigs = [self.managedObjectContext executeFetchRequest:mainFetchRequest error:&error];
	switch ( userConfigs.count ) {
		case 0:
			userConfig = [ILobbyStoreUserConfig insertNewUserConfigInContext:self.managedObjectContext];
			[self.managedObjectContext save:&error];
			break;
		case 1:
			userConfig = userConfigs[0];
			break;
		default:
			break;
	}

	return userConfig;
}


- (BOOL)loadDefaultPresentation {
	return [self loadPresentation:self.userConfig.defaultPresentation];
}


- (BOOL)loadPresentation:(ILobbyStorePresentation *)presentationStore {
	if ( presentationStore != nil && presentationStore.isReady ) {
		NSMutableArray *tracks = [NSMutableArray new];

		// create a new track from each track store
		for ( ILobbyStoreTrack *trackStore in presentationStore.tracks ) {
			// TODO: instantiate a new track configured against the store
		}

		self.tracks = [NSArray arrayWithArray:tracks];
		self.defaultTrack = tracks.count > 0 ? tracks[0] : nil;

		return YES;
	}
	else {
		return NO;
	}
}


- (NSURL *)presentationLocation {
	return [[NSUserDefaults standardUserDefaults] URLForKey:@"presentationLocation"];
}


- (void)setPresentationLocation:(NSURL *)presentationLocation {
	[[NSUserDefaults standardUserDefaults] setURL:presentationLocation forKey:@"presentationLocation"];
}


- (BOOL)delayInstall {
	return [[NSUserDefaults standardUserDefaults] boolForKey:@"delayInstall"];
}


- (void)setDelayInstall:(BOOL)delayInstall {
	[[NSUserDefaults standardUserDefaults] setBool:delayInstall forKey:@"delayInstall"];
}


- (BOOL)downloading {
	ILobbyPresentationDownloader *currentDowloader = self.presentationDownloader;
	return currentDowloader != nil && !currentDowloader.complete && !currentDowloader.canceled;
}


- (void)downloadPresentationForcingFullDownload:(BOOL)forceFullDownload {
	ILobbyPresentationDownloader *currentDownloader = self.presentationDownloader;
	if ( currentDownloader && !currentDownloader.complete ) {
		[self cancelPresentationDownload];
	}

	__block ILobbyStorePresentation *presentation;
	[self.managedObjectContext performBlockAndWait:^{
		presentation = [ILobbyStorePresentation insertNewPresentationInContext:self.managedObjectContext];

		//TODO: remote location should be from user instead of hard coded
		presentation.remoteLocation = @"http://ilobby.ornl.gov/dev/lobby2/tracks/";

		//TODO: local presentation path should be computed instead of hard coded
		presentation.path = [[ILobbyModel.documentDirectoryURL path] stringByAppendingPathComponent:@"Presentation"];
	}];

	self.presentationDownloader = [[ILobbyPresentationDownloader alloc] initWithPresentation:presentation completionHandler:^(ILobbyPresentationDownloader *downloader) {
		NSLog( @"presentation dowload complete..." );
	}];
}


- (void)setPresentationDownloader:(ILobbyPresentationDownloader *)presentationDownloader {
	ILobbyPresentationDownloader *oldDownloader = self.presentationDownloader;
	if ( oldDownloader != nil ) {
		[oldDownloader removeObserver:self forKeyPath:@"progress"];
	}

	if ( presentationDownloader != nil ) {
		[presentationDownloader addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew context:nil];
	}
	_presentationDownloader = presentationDownloader;
}


- (void)cancelPresentationDownload {
	[self.presentationDownloader cancel];
	[self updateProgress:self.presentationDownloader];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ( [object isKindOfClass:[ILobbyPresentationDownloader class]] ) {
		[self updateProgress:(ILobbyPresentationDownloader *)object];
	}
}


- (void)updateProgress:(ILobbyPresentationDownloader *)downloader {
	self.downloadProgress = downloader.progress;
}

@end
