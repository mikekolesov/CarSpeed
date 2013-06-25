//
//  CS_ViewController.h
//  CarSpeed
//
//  Created by Kolesov Michael on 6/14/13.
//  Copyright (c) 2013 Kolesov Michael. All rights reserved.
//

#import <CorePlot-CocoaTouch.h>
#import <UIKit/UIKit.h>

@interface CS_ViewController : UIViewController <CPTPlotDataSource, CPTAxisDelegate>
{
    CPTXYGraph *graph;
    
    // data source place
    NSMutableArray *dataForBluePlot;
    NSMutableArray *dataForRedPlot;
    
    // graph range
    NSInteger xRangeLocation;
    NSInteger xRangeLength;
    NSInteger yRangeLocation;
    NSInteger yRangeLength;
}

@property (readwrite, strong, nonatomic) NSMutableArray *dataForBluePlot;
@property (readwrite, strong, nonatomic) NSMutableArray *dataForRedPlot;
@property (strong, nonatomic) IBOutlet UIView *hostView;
@property (strong, nonatomic) IBOutlet UISegmentedControl *segmentedControl;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activ;

@end
