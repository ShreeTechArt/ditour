//
//  ILobbyConfigurationController.m
//  iLobby
//
//  Created by Pelaia II, Tom on 10/23/12.
//  Copyright (c) 2012 UT-Battelle ORNL. All rights reserved.
//

#import "ILobbyConfigurationController.h"
#import "ILobbyPresentationDownloader.h"


@interface ILobbyConfigurationController ()
@property (strong, nonatomic) ILobbyPresentationDownloader *presentationDownloader;
@end


@implementation ILobbyConfigurationController


- (void)setLobbyModel:(ILobbyModel *)lobbyModel {
	if ( _lobbyModel ) {
		[_lobbyModel removeObserver:self forKeyPath:@"downloadProgress"];
	}

	[lobbyModel addObserver:self forKeyPath:@"downloadProgress" options:NSKeyValueObservingOptionNew context:nil];

	_lobbyModel = lobbyModel;
}


// download the presentation now
- (IBAction)downloadPresentation:(id)sender {
	[self.lobbyModel downloadPresentation];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ( [object isKindOfClass:[ILobbyModel class]] ) {
		[self updateProgress];
	}
}


- (void)updateProgress {
	ILobbyProgress *progress = self.lobbyModel.downloadProgress;

	dispatch_async( dispatch_get_main_queue(), ^{
		self.downloadProgressLabel.text = progress.label;
		self.downloadProgressView.progress = progress.fraction;
	});
}


// event indicating that the presentation location has changed
- (IBAction)presentationLocationChanged:(id)sender {
	NSString *location = self.presentationLocationField.text;
	self.lobbyModel.presentationLocation = location != nil ? [NSURL URLWithString:location] : nil;
	if ( location )  [self downloadPresentation:sender];
}


- (void)viewDidLoad {
    [super viewDidLoad];

	// Do any additional setup after loading the view, typically from a nib.
	NSURL *presentationLocation = self.lobbyModel.presentationLocation;
	if ( presentationLocation ) {
		self.presentationLocationField.text = [presentationLocation description];
	}

	[self updateProgress];
}


- (void)viewWillDisappear:(BOOL)animated {
	if ( _lobbyModel ) {
		[_lobbyModel removeObserver:self forKeyPath:@"downloadProgress"];
	}
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark -
#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
    return NO;
}

@end
