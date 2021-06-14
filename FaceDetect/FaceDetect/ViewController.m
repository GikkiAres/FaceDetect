//
//  ViewController.m
//  FaceDetect
//
//  Created by Gikki Ares on 2021/6/14.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<
AVCaptureMetadataOutputObjectsDelegate
>
{
	AVCaptureSession * mavCaptureSession;
	CALayer * mcaLayer_overlay;
	NSMutableDictionary * mdic_faceLayer;
	AVCaptureVideoPreviewLayer * mavCaptureVideoPreviewLayer;
}

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// Do any additional setup after loading the view.
	
	[self setupCaptureSession];
	[self setupCaptureDeviceInput];
	[self setupCaptureMetadataOutput];
	[self setupPreviewLayer];
	
		//OverlayLayer
	mcaLayer_overlay = [[CALayer alloc]init];
	mcaLayer_overlay.frame = self.view.bounds;
	mcaLayer_overlay.sublayerTransform = makePerspectiveTransform(1000);
	[mavCaptureVideoPreviewLayer addSublayer:mcaLayer_overlay];
	mdic_faceLayer = [NSMutableDictionary dictionary];
}


- (void)setupCaptureSession {
	mavCaptureSession = [[AVCaptureSession alloc]init];
}

- (void)setupCaptureDeviceInput{
	AVCaptureDeviceDiscoverySession *avCaptureDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession  discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
	AVCaptureDevice * avCaptureDevice = avCaptureDeviceDiscoverySession.devices.firstObject;
	AVCaptureDeviceInput * avCaptureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:avCaptureDevice error:nil];
	if([mavCaptureSession canAddInput:avCaptureDeviceInput]) {
		[mavCaptureSession addInput:avCaptureDeviceInput];
	}
}

- (void)setupCaptureMetadataOutput {
	AVCaptureMetadataOutput * avCaptureMetadataOutput = [[AVCaptureMetadataOutput alloc]init];
	if([mavCaptureSession canAddOutput:avCaptureMetadataOutput]) {
		[mavCaptureSession addOutput:avCaptureMetadataOutput];
	}
	avCaptureMetadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeFace];
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	[avCaptureMetadataOutput setMetadataObjectsDelegate:self queue:queue];
}

- (void)setupPreviewLayer {
	AVCaptureVideoPreviewLayer * avCaptureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc]init];
	mavCaptureVideoPreviewLayer = avCaptureVideoPreviewLayer;
	mavCaptureVideoPreviewLayer.session = mavCaptureSession;
	avCaptureVideoPreviewLayer.frame = self.view.bounds;
		//设置视频显示的方式
	[avCaptureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	avCaptureVideoPreviewLayer.backgroundColor = [UIColor blackColor].CGColor;
	[self.view.layer insertSublayer:avCaptureVideoPreviewLayer atIndex:0];
}



#pragma mark Delegate
-(void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self didDetectFaces:metadataObjects];
	});
}

	//转换坐标
- (NSArray <AVMetadataFaceObject *> *)transformedFacesFromFaces:(NSArray <AVMetadataFaceObject *> *)faces {
	NSMutableArray * marr_transformedFace = [NSMutableArray array];
	for(AVMetadataFaceObject * face in faces) {
		AVMetadataFaceObject * transformedFace = (AVMetadataFaceObject *)[mavCaptureVideoPreviewLayer transformedMetadataObjectForMetadataObject:face];
		
		NSLog(@"Did capture face with id:%li",face.faceID);
		NSLog(@"Origin bounds is:%@",NSStringFromCGRect(face.bounds));
		NSLog(@"Transformed bounds is:%@",NSStringFromCGRect(transformedFace.bounds));
		if(face.hasYawAngle) {
			NSLog(@"Yaw angle is %.2f",face.yawAngle);
		}
		if(face.hasRollAngle) {
			NSLog(@"Roll angle is %.2f",face.rollAngle);
		}
		if(transformedFace) {
			[marr_transformedFace addObject:transformedFace];
		}
	}
	return marr_transformedFace;
}

- (void)didDetectFaces:(NSArray<AVMetadataFaceObject *> *)faces {
	NSArray * arr_transformedFaces = [self transformedFacesFromFaces:faces];
	
		//上一个loop检测到的人脸,判断是否还在
	NSMutableArray * lostFaces = [mdic_faceLayer.allKeys mutableCopy];
	
	for(AVMetadataFaceObject * face in arr_transformedFaces) {
		NSNumber * faceId = @(face.faceID);
			//数组判断nsnumber是根据值来判断的
		[lostFaces removeObject:faceId];
		
			//人脸对应的layer
		CALayer * layer = mdic_faceLayer[faceId];
		if(!layer) {
			layer = [self makeFaceLayer];
			[mcaLayer_overlay addSublayer:layer];
			mdic_faceLayer[faceId] = layer;
		}
		layer.transform = CATransform3DIdentity;
		layer.frame = face.bounds;
		
			//绘制边框的相关参数
		if(face.hasRollAngle) {
			CATransform3D t = [self transformForRollAngle:face.rollAngle];
			layer.transform = CATransform3DConcat(layer.transform, t);
		}
		
		if(face.hasYawAngle) {
			CATransform3D t = [self transformForYawAngle:face.yawAngle];
			layer.transform = CATransform3DConcat(layer.transform, t);
		}
	}
	
		//移除没有了的face
	for(NSNumber * faceId in lostFaces) {
		CALayer * layer = mdic_faceLayer[faceId];
		[layer removeFromSuperlayer];
		[mdic_faceLayer removeObjectForKey:faceId];
	}
	
	
}

- (CALayer *)makeFaceLayer {
	CALayer * layer = [CALayer layer];
	layer.borderWidth = 5;
	layer.borderColor = [UIColor colorWithRed:0.188 green:0.517 blue:0.877 alpha:1.0].CGColor;
	return layer;
}

static CATransform3D makePerspectiveTransform(CGFloat eyePosition) {
	CATransform3D transform = CATransform3DIdentity;
	transform.m34 = -1.0 / eyePosition;
	return transform;
}

- (CATransform3D)transformForRollAngle:(CGFloat)angleInDegree {
	CGFloat rollAngleInRadian = angleInDegree * M_PI / 180;
	return CATransform3DMakeRotation(rollAngleInRadian,0.0f,0.0f,1.0f);
}

- (CATransform3D)transformForYawAngle:(CGFloat)angleInDegree {
	CGFloat angleInRadian = angleInDegree * M_PI / 180;
	CATransform3D yawTransform = CATransform3DMakeRotation(angleInRadian,0.0f,-1.0f,0.0f);
	return CATransform3DConcat(yawTransform, [self orientationTransform]);
}

- (CATransform3D)orientationTransform {
	CGFloat angle = 0.0;
	switch([UIDevice currentDevice].orientation) {
		case UIDeviceOrientationPortraitUpsideDown:
			angle = M_PI;
			break;
		case UIDeviceOrientationLandscapeRight:
			angle = -M_PI/2.0f;
			break;
		case UIDeviceOrientationLandscapeLeft:
			angle = M_PI/2.0f;
			break;
		default:
			angle = 0.0;
			break;
	}
	return CATransform3DMakeRotation(angle, 0.0f, 0.0f, 1.0f);
}

#pragma mark Event

- (IBAction)onClickStart:(id)sender {
	[mavCaptureSession startRunning];
}

- (IBAction)onClickStop:(id)sender {
	[mavCaptureSession stopRunning];
}


@end
