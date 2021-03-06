//
//  XMPPMessageCoreDataStorageObject.m
//  TinyChatter
//
//  Created by ling tsu hsuan on 4/7/12.
//  Copyright (c) 2012 jtg2078@hotmail.com. All rights reserved.
//

#import "XMPPMessageCoreDataStorageObject.h"

@interface XMPPMessageCoreDataStorageObject ()
@property(nonatomic, retain) XMPPJID    * primitiveJid;
@property(nonatomic, retain) NSString   * primitiveJidStr;
@property(nonatomic, retain) XMPPJID    * primitiveToJid;
@property(nonatomic, retain) NSString   * primitiveToJidStr;
@end


@implementation XMPPMessageCoreDataStorageObject

@dynamic body;
@dynamic fromMe;
@dynamic isFromMe;
@dynamic jid;
@dynamic jidStr;
@dynamic localTimestamp;
@dynamic message;
@dynamic messageStr;
@dynamic nickname;
@dynamic remoteTimestamp;
@dynamic streamBareJidStr;
@dynamic type;
@dynamic toJid;
@dynamic toJidStr;

@dynamic primitiveJid;
@dynamic primitiveJidStr;
@dynamic primitiveToJid;
@dynamic primitiveToJidStr;


#pragma mark Transient jid

- (XMPPJID *)jid
{
	// Create and cache on demand
	
	[self willAccessValueForKey:@"jid"];
	XMPPJID *tmp = self.primitiveJid;
	[self didAccessValueForKey:@"jid"];
	
	if (tmp == nil)
	{
		NSString *jidStr = self.jidStr;
		if (jidStr)
		{
			tmp = [XMPPJID jidWithString:jidStr];
			self.primitiveJid = tmp;
		}
	}
	
	return tmp;
}

- (void)setJid:(XMPPJID *)jid
{
	[self willChangeValueForKey:@"jid"];
	[self willChangeValueForKey:@"jidStr"];
	
	self.primitiveJid = jid;
	self.primitiveJidStr = [jid full];
	
	[self didChangeValueForKey:@"jid"];
	[self didChangeValueForKey:@"jidStr"];
}

- (void)setJidStr:(NSString *)jidStr
{
	[self willChangeValueForKey:@"jid"];
	[self willChangeValueForKey:@"jidStr"];
	
	self.primitiveJid = [XMPPJID jidWithString:jidStr];
	self.primitiveJidStr = jidStr;
	
	[self didChangeValueForKey:@"jid"];
	[self didChangeValueForKey:@"jidStr"];
}

- (XMPPJID *)toJid
{
	// Create and cache on demand
	
	[self willAccessValueForKey:@"toJid"];
	XMPPJID *tmp = self.primitiveToJid;
	[self didAccessValueForKey:@"toJid"];
	
	if (tmp == nil)
	{
		NSString *jidStr = self.toJidStr;
		if (jidStr)
		{
			tmp = [XMPPJID jidWithString:jidStr];
			self.primitiveToJid = tmp;
		}
	}
	
	return tmp;
}

- (void)setToJid:(XMPPJID *)jid
{
	[self willChangeValueForKey:@"toJid"];
	[self willChangeValueForKey:@"toJidStr"];
	
	self.primitiveToJid = jid;
	self.primitiveToJidStr = [jid full];
	
	[self didChangeValueForKey:@"toJid"];
	[self didChangeValueForKey:@"toJidStr"];
}

- (void)setToJidStr:(NSString *)jidStr
{
	[self willChangeValueForKey:@"toJid"];
	[self willChangeValueForKey:@"toJidStr"];
	
	self.primitiveToJid = [XMPPJID jidWithString:jidStr];
	self.primitiveToJidStr = jidStr;
	
	[self didChangeValueForKey:@"toJid"];
	[self didChangeValueForKey:@"toJidStr"];
}

#pragma mark Scalar

- (BOOL)isFromMe
{
	return [[self fromMe] boolValue];
}

- (void)setIsFromMe:(BOOL)value
{
	self.fromMe = [NSNumber numberWithBool:value];
}

@end
