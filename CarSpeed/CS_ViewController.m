//
//  CS_ViewController.m
//  CarSpeed
//
//  Created by Kolesov Michael on 6/14/13.
//  Copyright (c) 2013 Kolesov Michael. All rights reserved.
//

#import "CS_ViewController.h"
#import <my_global.h>
#import <mysql.h>


// Connection settings
#define SERVER      "80.73.202.140"
#define USER        "testuser"
#define PASSWD      "testuser"
#define SCHEME      "testdb"
#define PORT        3306

#define FIXED_DATE  1   //for debug only. comment to use current date
#ifdef FIXED_DATE
    #define FIXED_DATE_STR          @"2013_02_28"
    #define FIXED_DATE_AND_TIME_STR @"2013_02_28 19:30:00"
    #define FIXED_DATE_PREV_STR     @"2013_02_27"
#endif

// Device to show
NSString * device1 = @"355094045913393";
NSString * device2 = @"355094045745118";

#define LAST_DEVICE_HOURS 1 //comment to show last phone hours

// One hour in seconds
NSTimeInterval oneHour = 1 * 60 * 60;



@implementation CS_ViewController

@synthesize dataForBluePlot;
@synthesize dataForRedPlot;
@synthesize segmentedControl;
@synthesize activ;

#pragma mark -
#pragma mark UI methods

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    // set graph range defaults
    xRangeLocation = 0;
    xRangeLength = 6 * oneHour;
    yRangeLocation = -10;
    yRangeLength = 100;
    
    // segment control setup
    [segmentedControl addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    
    [self plotSetup];
    
    // run sql thread
    [NSThread detachNewThreadSelector:@selector(sqlThread) toTarget:self withObject:nil];
}


-(void) segmentChanged
{
    NSInteger oldXRangeLength = xRangeLength;
    
    // change x range lenth
    switch (segmentedControl.selectedSegmentIndex) {
        case 0:
            xRangeLength = oneHour;
            break;
        case 1:
            xRangeLength = 6 * oneHour;
            break;
        case 2:
            xRangeLength = 12 * oneHour;
            break;
        case 3:
            xRangeLength = 24 * oneHour;
            break;
            
        default:
            xRangeLength = 6 * oneHour;
            break;
    }
    
    //update graph with last range
    xRangeLocation = (xRangeLocation + oldXRangeLength) - xRangeLength;
    [self changePlotRange];
    [self changeGraphAxis];
    [graph reloadData];
}

#pragma mark -
#pragma mark MYSQL Connector Methods

-(void) sqlThread
{
    MYSQL * conn;
    MYSQL_RES *result;
    MYSQL_ROW row;
    int num_fields;
    
    while (1) { // top loop for init, connect, query, close
    
        //short delay if reinit and reconnect
        sleep(1);
        
        // indicate busy
        runOnMainThread(^{
            [activ startAnimating];
        });
        
        //show version of connector and init
        printf("MySQL client version: %s\n", mysql_get_client_info());
        conn = mysql_init(NULL);
        if (conn == NULL) {
            printf("Error %u: %s\n", mysql_errno(conn), mysql_error(conn));
            continue;
        }
        
        NSLog(@"Connecting to server:%s, user:%s, scheme:%s ..", SERVER, USER, SCHEME);
        if (mysql_real_connect(conn, SERVER, USER, PASSWD, SCHEME, PORT, NULL, 0) == NULL) {
            printf("Error %u: %s\n", mysql_errno(conn), mysql_error(conn));
            continue;
        }
        else {
            NSLog(@"Done");
            printf("MySQL server version: %s\n", mysql_get_server_info(conn));
        }
        
        // stop indicating busy
        runOnMainThread(^{
            [activ stopAnimating];
        });

        // set date format
        NSDateFormatter * dateTimeFormater = [[NSDateFormatter alloc] init];
        
        while (1) { // internal loop for query 
            @autoreleasepool {
                
            #ifdef FIXED_DATE
                // simulate custom date (for debug only)
                [dateTimeFormater setDateFormat:@"yyyy_MM_dd HH:mm:ss"];
                NSDate *curDate = [dateTimeFormater dateFromString:FIXED_DATE_AND_TIME_STR];
                [dateTimeFormater setDateFormat:@"yyyy_MM_dd"];
                NSString *curDateStr = FIXED_DATE_STR; 
                //NSString *prevDateStr = FIXED_DATE_PREV_STR;
            #else
                //get current date and time
                NSDate *curDate = [NSDate date];    
                [dateTimeFormater setDateFormat:@"yyyy_MM_dd"];
                NSString *curDateStr = [dateTimeFormater stringFromDate:curDate];
                // TODO
                //NSString *prevDateStr = @"????_??_??";
            #endif
            
            // parse time
            // get ref date (DATE 00:00:00) 
            NSDate *refDate = [dateTimeFormater dateFromString:curDateStr];
            // get current time in seconds since ref date
            NSTimeInterval curTime = [curDate timeIntervalSinceDate:refDate];
            
            //NSLog(@"%f", curTime);
            //NSLog(@"ref->%@, curDateStr->%@", refDate, curDateStr);
            
            //setup query
            // current date
            NSString * queryCur = [NSString stringWithFormat:
                                @"SELECT nodes_%@.time, param_values_%@.param_value, nodes_%@.device FROM nodes_%@, param_values_%@ WHERE nodes_%@.node_id=param_values_%@.node_id AND param_values_%@.param_id=1 AND (nodes_%@.device=%@ OR nodes_%@.device=%@)",
                                curDateStr, curDateStr, curDateStr, curDateStr, curDateStr, curDateStr, curDateStr, curDateStr, curDateStr, device1, curDateStr, device2];
            
            /*
            // previous date
            NSString * queryPrev = [NSString stringWithFormat:
                                @"SELECT nodes_%@.time, param_values_%@.param_value, nodes_%@.device FROM nodes_%@, param_values_%@ WHERE nodes_%@.node_id=param_values_%@.node_id AND param_values_%@.param_id=1 AND (nodes_%@.device=%@ OR nodes_%@.device=%@)",
                                prevDateStr, prevDateStr, prevDateStr, prevDateStr, prevDateStr, prevDateStr, prevDateStr, prevDateStr, prevDateStr, device1, prevDateStr, device2];
            
            // union dates
            NSString * queryUnion = [NSString stringWithFormat:@"%@ UNION %@", queryPrev, queryCur];
            
            NSLog(@"%@", queryUnion);*/
            
            //NSLog(@"Send Query..");
            
            if (mysql_query(conn, [queryCur UTF8String]) ) {
                printf("Error %u: %s\n", mysql_errno(conn), mysql_error(conn));
                break; // close connection and try from beginning (init, etc..)
            }
            
            result = mysql_store_result(conn);
            
            num_fields = mysql_num_fields(result);
            
            // Add some data here
            NSMutableArray *newData1 = [NSMutableArray array];
            NSMutableArray *newData2 = [NSMutableArray array];
            
            NSDateFormatter *sqlDateFormater = [[NSDateFormatter alloc] init];
            [sqlDateFormater setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            //[sqlDateFormater setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
            
            
            NSTimeInterval lastX = 0;
            NSInteger maxSpeed = 0;
            while ((row = mysql_fetch_row(result)))
            {
                /*for(int i = 0; i < num_fields; i++)
                {
                    printf("%s ", row[i] ? row[i] : "NULL");
                }
                printf("\n");*/
                
                // convert sql time string to nsdate
                NSString *strSqlDate = [NSString stringWithCString:row[0] encoding:NSUTF8StringEncoding];
                NSDate *dateSqlDate = [sqlDateFormater dateFromString:strSqlDate];
                
                // get number of seconds from beggining of the date
                NSTimeInterval x = [dateSqlDate timeIntervalSinceDate:refDate];
                NSInteger y = atoi(row[1]);
                NSString *device = [NSString stringWithCString:row[2] encoding:NSUTF8StringEncoding];
                if ([device isEqualToString:device1]) {
                    [newData1 addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSDecimalNumber numberWithFloat:x], @"x",
                                         [NSDecimalNumber numberWithFloat:y], @"y",
                                         nil]];
                } else {
                    [newData2 addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSDecimalNumber numberWithFloat:x], @"x",
                                         [NSDecimalNumber numberWithFloat:y], @"y",
                                         nil]];
                }
                
                
                // calculate last time and max speed
                #ifdef LAST_DEVICE_HOURS
                    lastX = x;
                #endif
                maxSpeed = maxSpeed > y ? maxSpeed : y;
            }
            
            #ifndef LAST_DEVICE_HOURS
                lastX = curTime;
            #endif
            // update plot space coordinates
            xRangeLocation = lastX - xRangeLength;
            yRangeLength = maxSpeed + 15;
            
            if (![newData1 count] || ![newData1 count])
                NSLog(@"Empty data set[s]!");
            
            // update graph on main GCD queue
            runOnMainThread (^{
                    
                    // save data
                    dataForBluePlot = newData1;
                    dataForRedPlot = newData2;
                    
                    [self changePlotRange];
                    [self changeGraphAxis];
                    
                    [graph reloadData];
            });
            
            mysql_free_result(result);
                
            } // end of @autoreleasepool
            
            // delay between queries
            sleep(1);
           
        } // end of query while 
        
        NSLog(@"Close connection");
        mysql_close(conn);
        
    } // end of top while
}

#pragma mark -
#pragma mark Plot Setup Methods

-(void) plotSetup
{    
    // Create graph from theme
    graph = [[CPTXYGraph alloc] initWithFrame:CGRectZero];
    CPTTheme *theme = [CPTTheme themeNamed:kCPTDarkGradientTheme];
    [graph applyTheme:theme];
    CPTGraphHostingView *hostingView = (CPTGraphHostingView *)self.hostView;
    hostingView.collapsesLayers = NO;
    hostingView.hostedGraph     = graph;
    
    graph.paddingLeft   = 10.0;
    graph.paddingTop    = 10.0;
    graph.paddingRight  = 10.0;
    graph.paddingBottom = 10.0;
    
    // Setup plot space
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)graph.defaultPlotSpace;
    plotSpace.allowsUserInteraction = NO;
    [self changePlotRange]; // update to defaults
    
    
    // Axes
    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)graph.axisSet;
    CPTXYAxis *x          = axisSet.xAxis;
    
    // grid lines
    CPTMutableLineStyle *gridLineStyle = [CPTMutableLineStyle lineStyle];
    gridLineStyle.lineWidth = 0.25;
    gridLineStyle.lineColor = [CPTColor grayColor];
    x.majorGridLineStyle = gridLineStyle;
    
    //x.majorIntervalLength         = CPTDecimalFromFloat(oneHour); // in changeGraphAxis
    x.orthogonalCoordinateDecimal = CPTDecimalFromString(@"0"); // y point
    x.minorTicksPerInterval       = 4;
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"H"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    CPTTimeFormatter *timeFormatter = [[CPTTimeFormatter alloc] initWithDateFormatter:dateFormatter];
    x.labelFormatter = timeFormatter;
    
    
    CPTXYAxis *y = axisSet.yAxis;
    //grid lines
    gridLineStyle.lineWidth = 0.25;
    gridLineStyle.lineColor = [CPTColor greenColor];
    y.majorGridLineStyle = gridLineStyle;
    y.majorIntervalLength         = CPTDecimalFromString(@"10");
    y.minorTicksPerInterval       = 1;
    //y.orthogonalCoordinateDecimal = CPTDecimalFromFloat(0); // in changeGraphAxis
    NSArray *exclusionRanges      = [NSArray arrayWithObjects:
                                     [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(0) length:CPTDecimalFromFloat(-20.0)],
                                     nil];
    y.labelExclusionRanges = exclusionRanges;
    y.delegate             = self;
    
    [self changeGraphAxis];// update to defaults
    
    // Create a blue plot area
    CPTScatterPlot *blueLinePlot  = [[CPTScatterPlot alloc] init];
    CPTMutableLineStyle *lineStyle = [CPTMutableLineStyle lineStyle];
    lineStyle.miterLimit        = 1.0f;
    lineStyle.lineWidth         = 3.0f;
    lineStyle.lineColor         = [CPTColor blueColor];
    blueLinePlot.dataLineStyle = lineStyle;
    blueLinePlot.identifier    = @"Blue Plot";
    blueLinePlot.title         = @"Car A";
    blueLinePlot.dataSource    = self;
    [graph addPlot:blueLinePlot];
    
    
    // Create a red plot area
    CPTScatterPlot *redLinePlot  = [[CPTScatterPlot alloc] init];
    lineStyle = [CPTMutableLineStyle lineStyle];
    lineStyle.miterLimit        = 1.0f;
    lineStyle.lineWidth         = 3.0f;
    lineStyle.lineColor         = [CPTColor redColor];
    redLinePlot.dataLineStyle = lineStyle;
    redLinePlot.identifier    = @"Red Plot";
    redLinePlot.title         = @"Car B";
    redLinePlot.dataSource    = self;
    [graph addPlot:redLinePlot];
    
    // add legend
    graph.legend = [CPTLegend legendWithGraph:graph];
    graph.legend.textStyle = x.titleTextStyle;
    graph.legendAnchor = CPTRectAnchorTopRight;
    graph.legendDisplacement = CGPointMake(-10.0, -10.0);
    
}

// change visible plot range
-(void)changePlotRange
{
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)graph.defaultPlotSpace;
    NSInteger xMargin = xRangeLength/10;
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(xRangeLocation - xMargin) length:CPTDecimalFromFloat(xRangeLength + xMargin*2)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(yRangeLocation) length:CPTDecimalFromFloat(yRangeLength)];

}

// change axis positions
-(void) changeGraphAxis
{
    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)graph.axisSet;
    CPTXYAxis *x          = axisSet.xAxis;
    NSInteger xMargin = xRangeLength/10;
    x.minorGridLineStyle = nil;
    
    if (xRangeLength == oneHour) {
        x.majorIntervalLength = CPTDecimalFromFloat(oneHour);
        x.minorTicksPerInterval = 4;
        
        // add grid lines for minor ticks
        CPTMutableLineStyle *gridLineStyle = [CPTMutableLineStyle lineStyle];
        gridLineStyle.lineWidth = 0.10;
        gridLineStyle.lineColor = [CPTColor grayColor];
        x.minorGridLineStyle = gridLineStyle;
    }
    else if (xRangeLength == 6*oneHour) {
        x.majorIntervalLength = CPTDecimalFromFloat(oneHour);
        x.minorTicksPerInterval = 1;
    }
    else if (xRangeLength == 12*oneHour) {
        x.majorIntervalLength = CPTDecimalFromFloat(2*oneHour);
        x.minorTicksPerInterval = 0;
    }
    else if (xRangeLength == 24*oneHour) {
        x.majorIntervalLength = CPTDecimalFromFloat(4*oneHour);
        x.minorTicksPerInterval = 0;
    }

    
    CPTXYAxis *y = axisSet.yAxis;
    // change origin
    y.orthogonalCoordinateDecimal = CPTDecimalFromFloat(xRangeLocation + xMargin); // x point
    
    // update grid range
    x.gridLinesRange = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(0.0) length:CPTDecimalFromFloat(yRangeLength)];
    y.gridLinesRange = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(xRangeLocation + xMargin) length:CPTDecimalFromFloat(xRangeLength + xMargin*2)];
    
    // hide left of x axis
    NSArray *exclusionRanges      = [NSArray arrayWithObjects:
                                     [CPTPlotRange plotRangeWithLocation:CPTDecimalFromFloat(xRangeLocation + xMargin) length:CPTDecimalFromFloat(-xRangeLength)],
                                     nil];
    x.labelExclusionRanges = exclusionRanges;
}

#pragma mark -
#pragma mark Plot Data Source Methods

-(NSUInteger)numberOfRecordsForPlot:(CPTPlot *)plot
{
    if ( [(NSString *)plot.identifier isEqualToString:@"Blue Plot"] )
        return [dataForBluePlot count];
    else
        return [dataForRedPlot count];
}

-(NSNumber *)numberForPlot:(CPTPlot *)plot field:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
    NSString *key = (fieldEnum == CPTScatterPlotFieldX ? @"x" : @"y");

    if ( [(NSString *)plot.identifier isEqualToString:@"Blue Plot"] )
        return [[dataForBluePlot objectAtIndex:index] valueForKey:key];
    else
        return [[dataForRedPlot objectAtIndex:index] valueForKey:key];
}

#pragma mark -
#pragma mark Axis Delegate Methods

-(BOOL)axis:(CPTAxis *)axis shouldUpdateAxisLabelsAtLocations:(NSSet *)locations
{
    static CPTTextStyle *positiveStyle = nil;
    static CPTTextStyle *negativeStyle = nil;
    
    NSNumberFormatter *formatter = axis.labelFormatter;
    CGFloat labelOffset          = axis.labelOffset;
    NSDecimalNumber *zero        = [NSDecimalNumber zero];
    
    NSMutableSet *newLabels = [NSMutableSet set];
    
    for ( NSDecimalNumber *tickLocation in locations ) {
        CPTTextStyle *theLabelTextStyle;
        
        if ( [tickLocation isGreaterThanOrEqualTo:zero] ) {
            if ( !positiveStyle ) {
                CPTMutableTextStyle *newStyle = [axis.labelTextStyle mutableCopy];
                newStyle.color = [CPTColor greenColor];
                positiveStyle  = newStyle;
            }
            theLabelTextStyle = positiveStyle;
        }
        else {
            if ( !negativeStyle ) {
                CPTMutableTextStyle *newStyle = [axis.labelTextStyle mutableCopy];
                newStyle.color = [CPTColor redColor];
                negativeStyle  = newStyle;
            }
            theLabelTextStyle = negativeStyle;
        }
        
        NSString *labelString       = [formatter stringForObjectValue:tickLocation];
        CPTTextLayer *newLabelLayer = [[CPTTextLayer alloc] initWithText:labelString style:theLabelTextStyle];
        
        CPTAxisLabel *newLabel = [[CPTAxisLabel alloc] initWithContentLayer:newLabelLayer];
        newLabel.tickLocation = tickLocation.decimalValue;
        newLabel.offset       = labelOffset;
        
        [newLabels addObject:newLabel];
        
    }
    
    axis.axisLabels = newLabels;
    
    return NO;
}

// run block on main thread
void runOnMainThread(void (^ block)(void))
{
    if ([NSThread isMainThread]) {
        block();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
