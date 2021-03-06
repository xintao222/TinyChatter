//
//  XMPPChatHistoryCoreDataStorage.m
//  TinyChatter
//
//  Created by ling tsu hsuan on 4/7/12.
//  Copyright (c) 2012 jtg2078@hotmail.com. All rights reserved.
//

#import "XMPPChatHistoryCoreDataStorage.h"
#import "XMPPCoreDataStorageProtected.h"
#import "XMPPElement+Delay.h"
#import "XMPPLogging.h"


// Log levels: off, error, warn, info, verbose
#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_VERBOSE | XMPP_LOG_FLAG_TRACE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

#define AssertPrivateQueue() \
NSAssert(dispatch_get_current_queue() == storageQueue, @"Private method: MUST run on storageQueue");

@interface XMPPChatHistoryCoreDataStorage ()
{
	/* Inherited from XMPPCoreDataStorage
     
     NSString *databaseFileName;
     NSUInteger saveThreshold;
     
     dispatch_queue_t storageQueue;
     
     */
	
	NSString *messageEntityName;
    NSString *chatHistoryEntityName;
	
	NSTimeInterval maxMessageAge;
	NSTimeInterval deleteInterval;
	
	NSMutableSet *pausedMessageDeletion;
	
	dispatch_time_t lastDeleteTime;
	dispatch_source_t deleteTimer;
}

- (NSEntityDescription *)messageEntity:(NSManagedObjectContext *)moc;
- (NSEntityDescription *)chatHistoryEntityName:(NSManagedObjectContext *)moc;

- (void)performDelete;
- (void)destroyDeleteTimer;
- (void)updateDeleteTimer;
- (void)createAndStartDeleteTimer;

@end

@implementation XMPPChatHistoryCoreDataStorage

static XMPPChatHistoryCoreDataStorage *sharedInstance;

+ (XMPPChatHistoryCoreDataStorage *)sharedInstance
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		sharedInstance = [[XMPPChatHistoryCoreDataStorage alloc] initWithDatabaseFilename:nil];
	});
	
	return sharedInstance;
}

- (void)commonInit
{
	XMPPLogTrace();
	[super commonInit];
	
	// This method is invoked by all public init methods of the superclass
	
	messageEntityName = [NSStringFromClass([XMPPMessageCoreDataStorageObject class]) retain];
    chatHistoryEntityName = [NSStringFromClass([XMPPChatHistoryCoreDataStorageObject class]) retain];
	
	maxMessageAge  = (60 * 60 * 24 * 7); // 7 days
	deleteInterval = (60 * 5);           // 5 days
	
	pausedMessageDeletion = [[NSMutableSet alloc] init];
}

- (void)dealloc
{
	[self destroyDeleteTimer];
    [messageEntityName release];
    [chatHistoryEntityName release];
    [pausedMessageDeletion release];
    
    [super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)messageEntityName
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		result = messageEntityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setMessageEntityName:(NSString *)newMessageEntityName
{
	dispatch_block_t block = ^{
		messageEntityName = newMessageEntityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSString *)chatHistoryEntityName
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		result = chatHistoryEntityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setChatHistoryEntityName:(NSString *)newMessageEntityName
{
	dispatch_block_t block = ^{
		chatHistoryEntityName = newMessageEntityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSTimeInterval)maxMessageAge
{
	__block NSTimeInterval result = 0;
	
	dispatch_block_t block = ^{
		result = maxMessageAge;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setMaxMessageAge:(NSTimeInterval)age
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSTimeInterval oldMaxMessageAge = maxMessageAge;
		NSTimeInterval newMaxMessageAge = age;
		
		maxMessageAge = age;
		
		// There are several cases we need to handle here.
		// 
		// 1. If the maxAge was previously enabled and it just got disabled,
		//    then we need to stop the deleteTimer. (And we might as well release it.)
		// 
		// 2. If the maxAge was previously disabled and it just got enabled,
		//    then we need to setup the deleteTimer. (Plus we might need to do an immediate delete.)
		// 
		// 3. If the maxAge was increased,
		//    then we don't need to do anything.
		// 
		// 4. If the maxAge was decreased,
		//    then we should do an immediate delete.
		
		BOOL shouldDeleteNow = NO;
		
		if (oldMaxMessageAge > 0.0)
		{
			if (newMaxMessageAge <= 0.0)
			{
				// Handles #1
				[self destroyDeleteTimer];
			}
			else if (oldMaxMessageAge > newMaxMessageAge)
			{
				// Handles #4
				shouldDeleteNow = YES;
			}
			else
			{
				// Handles #3
				// Nothing to do now
			}
		}
		else if (newMaxMessageAge > 0.0)
		{
			// Handles #2
			shouldDeleteNow = YES;
		}
		
		if (shouldDeleteNow)
		{
			[self performDelete];
			
			if (deleteTimer)
				[self updateDeleteTimer];
			else
				[self createAndStartDeleteTimer];
		}
	}};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSTimeInterval)deleteInterval
{
	__block NSTimeInterval result = 0;
	
	dispatch_block_t block = ^{
		result = deleteInterval;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setDeleteInterval:(NSTimeInterval)interval
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		deleteInterval = interval;
		
		// There are several cases we need to handle here.
		// 
		// 1. If the deleteInterval was previously enabled and it just got disabled,
		//    then we need to stop the deleteTimer. (And we might as well release it.)
		// 
		// 2. If the deleteInterval was previously disabled and it just got enabled,
		//    then we need to setup the deleteTimer. (Plus we might need to do an immediate delete.)
		// 
		// 3. If the deleteInterval increased, then we need to reset the timer so that it fires at the later date.
		// 
		// 4. If the deleteInterval decreased, then we need to reset the timer so that it fires at an earlier date.
		//    (Plus we might need to do an immediate delete.)
		
		if (deleteInterval > 0.0)
		{
			if (deleteTimer == NULL)
			{
				// Handles #2
				// 
				// Since the deleteTimer uses the lastDeleteTime to calculate it's first fireDate,
				// if a delete is needed the timer will fire immediately.
				
				[self createAndStartDeleteTimer];
			}
			else
			{
				// Handles #3
				// Handles #4
				// 
				// Since the deleteTimer uses the lastDeleteTime to calculate it's first fireDate,
				// if a save is needed the timer will fire immediately.
				
				[self updateDeleteTimer];
			}
		}
		else if (deleteTimer)
		{
			// Handles #1
			
			[self destroyDeleteTimer];
		}
	}};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (void)pauseOldMessageDeletionForEntity:(XMPPJID *)entityJID
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[pausedMessageDeletion addObject:[entityJID bareJID]];
	}};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (void)resumeOldMessageDeletionForEntity:(XMPPJID *)entityJID
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[pausedMessageDeletion removeObject:[entityJID bareJID]];
		[self performDelete];
	}};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Overrides
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)didCreateManagedObjectContext
{
	XMPPLogTrace();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)performDelete
{
	if (maxMessageAge <= 0.0) return;
	
	NSDate *minLocalTimestamp = [NSDate dateWithTimeIntervalSinceNow:(maxMessageAge * -1.0)];
	
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSEntityDescription *messageEntity = [self messageEntity:moc];
	
	NSPredicate *predicate;
	if ([pausedMessageDeletion count] > 0)
	{
		predicate = [NSPredicate predicateWithFormat:@"localTimestamp <= %@ AND jidStr NOT IN %@",
                     minLocalTimestamp, pausedMessageDeletion];
	}
	else
	{
		predicate = [NSPredicate predicateWithFormat:@"localTimestamp <= %@", minLocalTimestamp];
	}
	
	NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	[fetchRequest setEntity:messageEntity];
	[fetchRequest setPredicate:predicate];
	[fetchRequest setFetchBatchSize:saveThreshold];
	
	NSError *error = nil;
	NSArray *oldMessages = [moc executeFetchRequest:fetchRequest error:&error];
	
	if (error)
	{
		XMPPLogWarn(@"%@: %@ - fetch error: %@", THIS_FILE, THIS_METHOD, error);
	}
	
	NSUInteger unsavedCount = [self numberOfUnsavedChanges];
	
	for (XMPPMessageCoreDataStorageObject *oldMessage in oldMessages)
	{
		[moc deleteObject:oldMessage];
		
		if (++unsavedCount >= saveThreshold)
		{
			[self save];
			unsavedCount = 0;
		}
	}
	
	lastDeleteTime = dispatch_time(DISPATCH_TIME_NOW, 0);
}

- (void)destroyDeleteTimer
{
	if (deleteTimer)
	{
		dispatch_source_cancel(deleteTimer);
		dispatch_release(deleteTimer);
		deleteTimer = NULL;
	}
}

- (void)updateDeleteTimer
{
	if ((deleteTimer != NULL) && (deleteInterval > 0.0) && (maxMessageAge > 0.0))
	{
		uint64_t interval = deleteInterval * NSEC_PER_SEC;
		dispatch_time_t startTime;
		
		if (lastDeleteTime > 0)
			startTime = dispatch_time(lastDeleteTime, interval);
		else
			startTime = dispatch_time(DISPATCH_TIME_NOW, interval);
		
		dispatch_source_set_timer(deleteTimer, startTime, interval, 1.0);
	}
}

- (void)createAndStartDeleteTimer
{
	if ((deleteTimer == NULL) && (deleteInterval > 0.0) && (maxMessageAge > 0.0))
	{
		deleteTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, storageQueue);
		
		dispatch_source_set_event_handler(deleteTimer, ^{ @autoreleasepool {
			
			[self performDelete];
			
		}});
		
		[self updateDeleteTimer];
		
		dispatch_resume(deleteTimer);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Protected API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)existsChatHistory:(XMPPMessage *)message stream:(XMPPStream *)xmppStream
{	
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSEntityDescription *chatHistoryEntity = [self chatHistoryEntityName:moc];
	
	XMPPJID *messageJID = [message from];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"jidStr == %@", messageJID];
	
	NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	[fetchRequest setEntity:chatHistoryEntity];
	[fetchRequest setPredicate:predicate];
	[fetchRequest setFetchLimit:1];
    
	NSError *error = nil;
	NSArray *results = [moc executeFetchRequest:fetchRequest error:&error];
	
	if (error)
	{
		XMPPLogError(@"%@: %@ - Fetch error: %@", THIS_FILE, THIS_METHOD, error);
	}
	
	return ([results count] > 0);
}

/**
 * Optional override hook for general extensions.
 * 
 * @see insertMessage:outgoing:forRoom:stream:
 **/
- (void)didInsertMessage:(XMPPMessageCoreDataStorageObject *)message
{
	// Override me if you're extending the XMPPChatHistoryCoreDataStorage class to add additional properties.
	// You can update your additional properties here.
	// 
	// At this point the standard properties have already been set.
	// So you can, for example, access the XMPPMessage via message.message.
}

/**
 * Optional override hook for complete customization.
 * Override me if you need to do specific custom work when inserting a message.
 * 
 * @see didInsertMessage:
 **/
- (void)insertMessage:(XMPPMessage *)message
             outgoing:(BOOL)isOutgoing
               stream:(XMPPStream *)xmppStream
{
	// Extract needed information
	XMPPJID *messageJID = [message from];
	
	NSDate *localTimestamp;
	NSDate *remoteTimestamp;
	
	if (isOutgoing)
	{
		localTimestamp = [NSDate date];
		remoteTimestamp = nil;
	}
	else
	{
		remoteTimestamp = [message delayedDeliveryDate];
		if (remoteTimestamp) {
			localTimestamp = remoteTimestamp;
		}
		else {
			localTimestamp = [NSDate date];
		}
	}
	
	NSString *messageBody = [[message elementForName:@"body"] stringValue];
	
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSString *streamBareJidStr = [[self myJIDForXMPPStream:xmppStream] bare];
	
	NSEntityDescription *messageEntity = [self messageEntity:moc];
	
	// Add to database
	
	XMPPMessageCoreDataStorageObject *entityMessage = [(XMPPMessageCoreDataStorageObject *)[[NSManagedObject alloc] initWithEntity:messageEntity insertIntoManagedObjectContext:nil] autorelease];
	
	entityMessage.message = message;
	entityMessage.jid = messageJID;
	entityMessage.nickname = [messageJID resource];
	entityMessage.body = messageBody;
	entityMessage.localTimestamp = localTimestamp;
	entityMessage.remoteTimestamp = remoteTimestamp;
	entityMessage.isFromMe = isOutgoing;
	entityMessage.streamBareJidStr = streamBareJidStr;
	
	[moc insertObject:entityMessage];      // Hook if subclassing XMPPRoomMessageCoreDataStorageObject (awakeFromInsert)
	[self didInsertMessage:entityMessage]; // Hook if subclassing XMPPRoomCoreDataStorage
}

- (void)didInsertChatHistory:(XMPPChatHistoryCoreDataStorageObject *)chatHistory
{
	// Override me if you're extending the XMPPChatHistoryCoreDataStorage class to add additional properties.
	// You can update your additional properties here.
	// 
	// At this point the standard properties have already been set.
	// So you can, for example, access the XMPPMessage via message.message.
}

- (void)insertChatHistory:(XMPPMessage *)message stream:(XMPPStream *)xmppStream
{
	// Extract needed information
	XMPPJID *messageJID = [message from];
	
	NSString *messageBody = [[message elementForName:@"body"] stringValue];
	
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSString *streamBareJidStr = [[self myJIDForXMPPStream:xmppStream] bare];
	
	NSEntityDescription *chatHistoryEntity = [self chatHistoryEntityName:moc];
	
	// Add to database
    
	XMPPChatHistoryCoreDataStorageObject *entityChatHistory = [(XMPPChatHistoryCoreDataStorageObject *)[[NSManagedObject alloc] initWithEntity:chatHistoryEntity insertIntoManagedObjectContext:nil] autorelease];
    
    /*
     @property (nonatomic, retain) NSString      * displayName;
     @property (nonatomic, retain) XMPPJID       * jid;              // Transient (proper type, not on disk)
     @property (nonatomic, retain) NSString      * jidStr;           // Shadow (binary data, written to disk)
     @property (nonatomic, retain) NSString      * nickname;
     @property (nonatomic, retain) NSString      * streamBareJidStr;
     @property (nonatomic, retain) NSString      * lastMessage;
     @property (nonatomic, retain) NSDate        * lastMessageTime;
     @property (nonatomic, retain) NSNumber      * lastMessageIsFromMe;
     @property (nonatomic, assign) BOOL          isLastMessageFromMe;
     */
	
	entityChatHistory.jid = messageJID;
	//entityChatHistory.nickname = [messageJID resource];
	entityChatHistory.streamBareJidStr = streamBareJidStr;
    entityChatHistory.lastMessage = messageBody;
    entityChatHistory.lastMessageTime = [NSDate date];
    
	
	[moc insertObject:entityChatHistory];      // Hook if subclassing XMPPChatHistoryCoreDataStorageObject (awakeFromInsert)
	[self didInsertChatHistory:entityChatHistory]; // Hook if subclassing XMPPChatHistoryCoreDataStorage
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSEntityDescription *)messageEntity:(NSManagedObjectContext *)moc
{
	// This method should be thread-safe.
	// So be sure to access the entity name through the property accessor.
	return [NSEntityDescription entityForName:[self messageEntityName] inManagedObjectContext:moc];
}

- (NSEntityDescription *)chatHistoryEntityName:(NSManagedObjectContext *)moc
{
	// This method should be thread-safe.
	// So be sure to access the entity name through the property accessor.
	return [NSEntityDescription entityForName:[self chatHistoryEntityName] inManagedObjectContext:moc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPChatHistoryStorage Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleOutgoingMessage:(XMPPMessage *)message xmppStream:(XMPPStream *)xmppStream
{
	XMPPLogTrace();
	
	[self scheduleBlock:^{
		
		[self insertMessage:message outgoing:YES stream:xmppStream];
        
	}];
}

- (void)handleIncomingMessage:(XMPPMessage *)message xmppStream:(XMPPStream *)xmppStream
{
	XMPPLogTrace();
	
	[self scheduleBlock:^{
		
		if ([self existsChatHistory:message stream:xmppStream] == NO)
		{
			[self insertChatHistory:message stream:xmppStream];
		}
		
        [self insertMessage:message outgoing:NO stream:xmppStream];
	}];
}

@end
