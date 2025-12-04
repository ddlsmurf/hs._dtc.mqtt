#import <Cocoa/Cocoa.h>
#import <LuaSkin/LuaSkin.h>
#import "deps/MQTT-Client-Framework/MQTTClient/MQTTClient/MQTTSessionManager.h"

#define USERDATA_TAG    "hs._dtc.mqtt"
static int refTable;

@interface HSMQTTClient : NSObject <MQTTSessionManagerDelegate>
@property (strong, nonatomic) MQTTSessionManager *manager;
@property int messageCallbackRef;
@property int stateCallbackRef;
@property (strong, nonatomic) NSString *onlineMessage;
@property (strong, nonatomic) NSString *onlineTopic;
@property MQTTQosLevel onlineQoS;
@property BOOL onlineRetain;
@property (strong, nonatomic) NSString *willTopic;
@property (strong, nonatomic) NSString *willMessage;
@property MQTTQosLevel willQoS;
@property BOOL willRetain;
@property BOOL publishWillOnDisconnect;
@property (atomic) BOOL pendingDisconnect;
@property (atomic) UInt16 willMessageId;
@end

@implementation HSMQTTClient

- (instancetype)init {
    self = [super init];
    if (self) {
        self.manager = [[MQTTSessionManager alloc] init];
        self.manager.delegate = self;
        self.messageCallbackRef = LUA_NOREF;
        self.stateCallbackRef = LUA_NOREF;
        self.publishWillOnDisconnect = YES;  // Default to publishing will on clean disconnect
    }
    return self;
}

- (void)sessionManager:(MQTTSessionManager *)sessionManager
     didReceiveMessage:(NSData *)data
               onTopic:(NSString *)topic
              retained:(BOOL)retained {
    if (self.messageCallbackRef != LUA_NOREF) {
        LuaSkin *skin = [LuaSkin sharedWithState:NULL];
        lua_State *L = [skin L];

        [skin pushLuaRef:refTable ref:self.messageCallbackRef];
        [skin pushNSObject:topic];
        [skin pushNSObject:data];
        lua_pushboolean(L, retained);

        if (![skin protectedCallAndTraceback:3 nresults:0]) {
            const char *errorMsg = lua_tostring(L, -1);
            [skin logError:[NSString stringWithFormat:@"%s: message callback error: %s",
                          USERDATA_TAG, errorMsg]];
            lua_pop(L, 1);
        }
    }
}

- (void)sessionManager:(MQTTSessionManager *)sessionManager
        didChangeState:(MQTTSessionManagerState)newState {
    if (self.stateCallbackRef != LUA_NOREF) {
        LuaSkin *skin = [LuaSkin sharedWithState:NULL];
        lua_State *L = [skin L];

        [skin pushLuaRef:refTable ref:self.stateCallbackRef];

        NSString *stateString;
        switch (newState) {
            case MQTTSessionManagerStateStarting:
                stateString = @"starting";
                break;
            case MQTTSessionManagerStateConnecting:
                stateString = @"connecting";
                break;
            case MQTTSessionManagerStateConnected:
                stateString = @"connected";
                break;
            case MQTTSessionManagerStateError:
                stateString = @"error";
                break;
            case MQTTSessionManagerStateClosing:
                stateString = @"closing";
                break;
            case MQTTSessionManagerStateClosed:
                stateString = @"closed";
                break;
            default:
                stateString = @"unknown";
        }

        [skin pushNSObject:stateString];

        if (![skin protectedCallAndTraceback:1 nresults:0]) {
            const char *errorMsg = lua_tostring(L, -1);
            [skin logError:[NSString stringWithFormat:@"%s: state callback error: %s",
                          USERDATA_TAG, errorMsg]];
            lua_pop(L, 1);
        }
    }

    // Auto-publish online message when connected
    if (newState == MQTTSessionManagerStateConnected &&
        self.onlineTopic && self.onlineMessage) {
        NSData *data = [self.onlineMessage dataUsingEncoding:NSUTF8StringEncoding];
        [self.manager sendData:data topic:self.onlineTopic qos:self.onlineQoS retain:self.onlineRetain];
    }
}

- (void)sessionManager:(MQTTSessionManager *)sessionManager didDeliverMessage:(UInt16)msgID {
    // Check if this is the will message we're waiting for
    if (self.pendingDisconnect && msgID == self.willMessageId) {
        NSLog(@"[hs._dtc.mqtt] Will message delivered, disconnecting now");
        self.pendingDisconnect = NO;
        [self.manager disconnectWithDisconnectHandler:nil];
    }
}

@end

#pragma mark - Helper Functions

static BOOL isValidQoS(lua_Integer qos) {
    return qos >= 0 && qos <= 2;
}

#pragma mark - Module Functions

/// hs._dtc.mqtt.new() -> client
/// Constructor
/// Creates a new MQTT client instance
///
/// Parameters:
///  * None
///
/// Returns:
///  * A new MQTT client object
///
/// Notes:
///  * The client ID should be specified in the connect() options
///  * If no client ID is provided during connection, a random one will be generated
static int mqtt_new(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TBREAK];

    HSMQTTClient *client = [[HSMQTTClient alloc] init];

    void **ud = (void**)lua_newuserdata(L, sizeof(id*));
    *ud = (__bridge_retained void*)client;

    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);

    return 1;
}

#pragma mark - Userdata Methods

/// hs._dtc.mqtt:connect(options) -> client
/// Method
/// Connects to an MQTT broker with the specified options
///
/// Parameters:
///  * options - A table containing connection options:
///    * host - (string, optional) Broker hostname or IP address (default: "localhost")
///    * port - (number, optional) Broker port (default: 1883)
///    * tls - (boolean, optional) Use TLS/SSL encryption (default: false)
///    * keepalive - (number, optional) Keep-alive interval in seconds (default: 60)
///    * clean - (boolean, optional) Clean session flag (default: true)
///    * username - (string, optional) Authentication username
///    * password - (string, optional) Authentication password
///    * clientId - (string, optional) Client identifier (random if not specified)
///    * willTopic - (string, optional) Last will topic
///    * willMessage - (string, optional) Last will message payload
///    * willQoS - (number, optional) Last will QoS level 0-2 (default: 0)
///    * willRetain - (boolean, optional) Last will retain flag (default: false)
///    * publishWillOnDisconnect - (boolean, optional) Publish will on clean disconnect (default: true)
///    * onlineTopic - (string, optional) Topic for automatic online message (defaults to willTopic if onlineMessage is set)
///    * onlineMessage - (string, optional) Payload for automatic online message
///    * onlineQoS - (number, optional) QoS for online message (defaults to willQoS if onlineMessage is set)
///    * onlineRetain - (boolean, optional) Retain flag for online message (defaults to willRetain if onlineMessage is set)
///
/// Returns:
///  * The client object for method chaining
///
/// Notes:
///  * The last will message is published by the broker when the client disconnects unexpectedly
///  * The online message is automatically published when connection succeeds
///  * Both willTopic and willMessage must be specified for last will to work
///  * Both onlineTopic and onlineMessage must be specified for auto-online to work
static int mqtt_connect(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TTABLE, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));

    // Parse connection options from table
    NSString *host = @"localhost";
    NSInteger port = 1883;
    BOOL tls = NO;
    NSInteger keepalive = 60;
    BOOL clean = YES;
    NSString *username = nil;
    NSString *password = nil;
    NSString *willTopic = nil;
    NSString *willMessage = nil;
    MQTTQosLevel willQoS = MQTTQosLevelAtMostOnce;
    BOOL willRetain = NO;
    NSString *clientId = [NSString stringWithFormat:@"hs_mqtt_%08x%08x",
                          arc4random(), arc4random()];

    if (lua_getfield(L, 2, "host") == LUA_TSTRING) {
        host = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "port") == LUA_TNUMBER) {
        port = lua_tointeger(L, -1);
        if (port < 1 || port > 65535) {
            return luaL_error(L, "port must be between 1 and 65535");
        }
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "tls") == LUA_TBOOLEAN) {
        tls = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "keepalive") == LUA_TNUMBER) {
        keepalive = lua_tointeger(L, -1);
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "clean") == LUA_TBOOLEAN) {
        clean = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "username") == LUA_TSTRING) {
        username = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "password") == LUA_TSTRING) {
        password = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "clientId") == LUA_TSTRING) {
        clientId = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "willTopic") == LUA_TSTRING) {
        willTopic = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "willMessage") == LUA_TSTRING) {
        willMessage = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "willQoS") == LUA_TNUMBER) {
        lua_Integer qosValue = lua_tointeger(L, -1);
        if (!isValidQoS(qosValue)) {
            return luaL_error(L, "willQoS must be 0, 1, or 2");
        }
        willQoS = (MQTTQosLevel)qosValue;
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "willRetain") == LUA_TBOOLEAN) {
        willRetain = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);

    // Handle online message configuration
    NSString *onlineTopic = nil;
    MQTTQosLevel onlineQoS = willQoS;  // Default to will QoS
    BOOL onlineRetain = willRetain;     // Default to will retain
    BOOL hasOnlineTopic = NO;
    BOOL hasOnlineQoS = NO;
    BOOL hasOnlineRetain = NO;

    if (lua_getfield(L, 2, "onlineMessage") == LUA_TSTRING) {
        client.onlineMessage = [skin toNSObjectAtIndex:-1];
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "onlineTopic") == LUA_TSTRING) {
        onlineTopic = [skin toNSObjectAtIndex:-1];
        hasOnlineTopic = YES;
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "onlineQoS") == LUA_TNUMBER) {
        lua_Integer qosValue = lua_tointeger(L, -1);
        if (!isValidQoS(qosValue)) {
            return luaL_error(L, "onlineQoS must be 0, 1, or 2");
        }
        onlineQoS = (MQTTQosLevel)qosValue;
        hasOnlineQoS = YES;
    }
    lua_pop(L, 1);

    if (lua_getfield(L, 2, "onlineRetain") == LUA_TBOOLEAN) {
        onlineRetain = lua_toboolean(L, -1);
        hasOnlineRetain = YES;
    }
    lua_pop(L, 1);

    // If onlineMessage is set but onlineTopic/QoS/retain are not, default to will settings
    if (client.onlineMessage) {
        client.onlineTopic = hasOnlineTopic ? onlineTopic : willTopic;
        client.onlineQoS = hasOnlineQoS ? onlineQoS : willQoS;
        client.onlineRetain = hasOnlineRetain ? onlineRetain : willRetain;
    } else {
        client.onlineTopic = onlineTopic;
        client.onlineQoS = onlineQoS;
        client.onlineRetain = onlineRetain;
    }

    // Handle publishWillOnDisconnect option (defaults to true)
    if (lua_getfield(L, 2, "publishWillOnDisconnect") == LUA_TBOOLEAN) {
        client.publishWillOnDisconnect = lua_toboolean(L, -1);
    } else {
        client.publishWillOnDisconnect = YES;  // Default to true
    }
    lua_pop(L, 1);

    // Store will settings for potential use on disconnect
    client.willTopic = willTopic;
    client.willMessage = willMessage;
    client.willQoS = willQoS;
    client.willRetain = willRetain;

    NSData *willData = willMessage ? [willMessage dataUsingEncoding:NSUTF8StringEncoding] : nil;
    BOOL hasAuth = (username != nil);
    BOOL hasWill = (willTopic != nil);

    [client.manager connectTo:host
                         port:port
                          tls:tls
                    keepalive:keepalive
                        clean:clean
                         auth:hasAuth
                         user:username
                         pass:password
                         will:hasWill
                    willTopic:willTopic
                      willMsg:willData
                      willQos:willQoS
               willRetainFlag:willRetain
                 withClientId:clientId
               securityPolicy:nil
                 certificates:nil
                protocolLevel:MQTTProtocolVersion311
               connectHandler:^(NSError *error) {
                   if (error) {
                       NSLog(@"MQTT connection error: %@", error.localizedDescription);
                   }
               }];

    lua_settop(L, 1);
    return 1;
}

/// hs._dtc.mqtt:disconnect() -> client
/// Method
/// Disconnects from the MQTT broker gracefully
///
/// Parameters:
///  * None
///
/// Returns:
///  * The client object for method chaining
///
/// Notes:
///  * By default, this will publish the last will message before disconnecting (if configured)
///  * Set publishWillOnDisconnect=false in connect options to disable this behavior
///  * The state callback will be invoked with "closing" and "closed" states
static int mqtt_disconnect(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));

    // Publish will message before disconnecting if configured to do so
    if (client.publishWillOnDisconnect && client.willTopic && client.willMessage) {
        NSData *willData = [client.willMessage dataUsingEncoding:NSUTF8StringEncoding];
        UInt16 msgId = [client.manager sendData:willData
                                          topic:client.willTopic
                                            qos:client.willQoS
                                         retain:client.willRetain];

        // For QoS 1 or 2, wait for delivery confirmation before disconnecting
        if (client.willQoS == MQTTQosLevelAtLeastOnce || client.willQoS == MQTTQosLevelExactlyOnce) {
            client.willMessageId = msgId;
            client.pendingDisconnect = YES;
            // Delegate will call disconnect when message is delivered
        } else {
            // QoS 0 has no delivery confirmation, add small delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                          dispatch_get_main_queue(), ^{
                [client.manager disconnectWithDisconnectHandler:nil];
            });
        }
    } else {
        [client.manager disconnectWithDisconnectHandler:nil];
    }

    lua_settop(L, 1);
    return 1;
}

/// hs._dtc.mqtt:publish(topic, message[, qos[, retain]]) -> msgid
/// Method
/// Publishes a message to the specified topic
///
/// Parameters:
///  * topic - (string) The topic to publish to
///  * message - (string) The message payload
///  * qos - (number, optional) Quality of Service level 0-2 (default: 0)
///  * retain - (boolean, optional) Retain flag (default: false)
///
/// Returns:
///  * Message ID (0 for QoS 0, non-zero for QoS 1 or 2)
///
/// Notes:
///  * QoS 0: At most once delivery (fire and forget)
///  * QoS 1: At least once delivery (acknowledged)
///  * QoS 2: Exactly once delivery (assured)
///  * Retained messages are stored by the broker and sent to new subscribers
static int mqtt_publish(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING, LS_TSTRING, LS_TNUMBER | LS_TNIL | LS_TOPTIONAL, LS_TBOOLEAN | LS_TNIL | LS_TOPTIONAL, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));
    NSString *topic = [skin toNSObjectAtIndex:2];
    NSString *message = [skin toNSObjectAtIndex:3];
    lua_Integer qosValue = (lua_gettop(L) >= 4) ? lua_tointeger(L, 4) : MQTTQosLevelAtMostOnce;
    MQTTQosLevel qos = (MQTTQosLevel)qosValue;
    BOOL retain = NO;
    if (lua_type(L, 5) == LUA_TBOOLEAN) {
        int retailValue = lua_toboolean(L, 5) ;
        retain = (BOOL)retailValue ;
    }
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    UInt16 msgId = [client.manager sendData:data topic:topic qos:qos retain:retain];

    lua_pushinteger(L, msgId);
    return 1;
}

/// hs._dtc.mqtt:subscribe(topic[, qos]) -> client
/// Method
/// Subscribes to one or more topics
///
/// Parameters:
///  * topic - Either:
///    * (string) A single topic to subscribe to
///    * (table) A table mapping topics to QoS levels: {["topic"] = qos, ...}
///  * qos - (number, optional) QoS level 0-2 (only used for single topic, default: 0)
///
/// Returns:
///  * The client object for method chaining
///
/// Notes:
///  * MQTT wildcards are supported: + for single level, # for multi-level
///  * Example: "home/+/temperature" or "sensors/#"
///  * Multiple subscriptions are additive - they don't replace existing ones
static int mqtt_subscribe(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING | LS_TTABLE, LS_TNUMBER | LS_TOPTIONAL, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));
    NSMutableDictionary *subscriptions = [NSMutableDictionary dictionary];

    if (lua_type(L, 2) == LUA_TSTRING) {
        NSString *topic = [skin toNSObjectAtIndex:2];
        lua_Integer qosValue = (lua_gettop(L) >= 3) ? lua_tointeger(L, 3) : MQTTQosLevelAtMostOnce;
        MQTTQosLevel qos = (MQTTQosLevel)qosValue;
        subscriptions[topic] = @(qos);
    } else if (lua_type(L, 2) == LUA_TTABLE) {
        lua_pushnil(L);
        while (lua_next(L, 2) != 0) {
            if (lua_type(L, -2) == LUA_TSTRING && lua_type(L, -1) == LUA_TNUMBER) {
                NSString *topic = [skin toNSObjectAtIndex:-2];
                lua_Integer qosValue = lua_tointeger(L, -1);
                MQTTQosLevel qos = (MQTTQosLevel)qosValue;
                subscriptions[topic] = @(qos);
            }
            lua_pop(L, 1);
        }
    }

    NSMutableDictionary *newSubs = [NSMutableDictionary dictionaryWithDictionary:client.manager.subscriptions];
    [newSubs addEntriesFromDictionary:subscriptions];
    client.manager.subscriptions = newSubs;

    lua_settop(L, 1);
    return 1;
}

/// hs._dtc.mqtt:unsubscribe(topics) -> client
/// Method
/// Unsubscribes from one or more topics
///
/// Parameters:
///  * topics - Either:
///    * (string) A single topic to unsubscribe from
///    * (table) An array of topic strings: {"topic1", "topic2", ...}
///
/// Returns:
///  * The client object for method chaining
static int mqtt_unsubscribe(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING | LS_TTABLE, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));
    NSMutableDictionary *newSubs = [NSMutableDictionary dictionaryWithDictionary:client.manager.subscriptions];

    if (lua_type(L, 2) == LUA_TSTRING) {
        NSString *topic = [skin toNSObjectAtIndex:2];
        [newSubs removeObjectForKey:topic];
    } else if (lua_type(L, 2) == LUA_TTABLE) {
        lua_pushnil(L);
        while (lua_next(L, 2) != 0) {
            if (lua_type(L, -1) == LUA_TSTRING) {
                NSString *topic = [skin toNSObjectAtIndex:-1];
                [newSubs removeObjectForKey:topic];
            }
            lua_pop(L, 1);
        }
    }

    client.manager.subscriptions = newSubs;

    lua_settop(L, 1);
    return 1;
}

/// hs._dtc.mqtt:setMessageCallback(fn) -> client
/// Method
/// Sets the callback function for received messages
///
/// Parameters:
///  * fn - A function to be called when messages are received, or nil to remove the callback
///    * The function will be called with three arguments:
///      * topic - (string) The topic the message was received on
///      * message - (string) The message payload as a string
///      * retained - (boolean) Whether this is a retained message
///
/// Returns:
///  * The client object for method chaining
///
/// Notes:
///  * Only one message callback can be active at a time
///  * Setting a new callback replaces any existing one
static int mqtt_setMessageCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));

    client.messageCallbackRef = [skin luaUnref:refTable ref:client.messageCallbackRef];

    if (lua_type(L, 2) == LUA_TFUNCTION) {
        lua_pushvalue(L, 2);
        client.messageCallbackRef = [skin luaRef:refTable];
    }

    lua_settop(L, 1);
    return 1;
}

/// hs._dtc.mqtt:setStateCallback(fn) -> client
/// Method
/// Sets the callback function for connection state changes
///
/// Parameters:
///  * fn - A function to be called when the connection state changes, or nil to remove the callback
///    * The function will be called with one argument:
///      * state - (string) One of: "starting", "connecting", "connected", "error", "closing", "closed"
///
/// Returns:
///  * The client object for method chaining
///
/// Notes:
///  * Only one state callback can be active at a time
///  * Setting a new callback replaces any existing one
///  * The "connected" state indicates successful connection
///  * The "error" state indicates connection failure
static int mqtt_setStateCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));

    client.stateCallbackRef = [skin luaUnref:refTable ref:client.stateCallbackRef];

    if (lua_type(L, 2) == LUA_TFUNCTION) {
        lua_pushvalue(L, 2);
        client.stateCallbackRef = [skin luaRef:refTable];
    }

    lua_settop(L, 1);
    return 1;
}

/// hs._dtc.mqtt:state() -> string
/// Method
/// Returns the current connection state
///
/// Parameters:
///  * None
///
/// Returns:
///  * A string representing the current state: "starting", "connecting", "connected", "error", "closing", "closed", or "unknown"
static int mqtt_state(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));

    NSString *stateString;
    switch (client.manager.state) {
        case MQTTSessionManagerStateStarting:
            stateString = @"starting";
            break;
        case MQTTSessionManagerStateConnecting:
            stateString = @"connecting";
            break;
        case MQTTSessionManagerStateConnected:
            stateString = @"connected";
            break;
        case MQTTSessionManagerStateError:
            stateString = @"error";
            break;
        case MQTTSessionManagerStateClosing:
            stateString = @"closing";
            break;
        case MQTTSessionManagerStateClosed:
            stateString = @"closed";
            break;
        default:
            stateString = @"unknown";
    }

    [skin pushNSObject:stateString];
    return 1;
}

static int userdata_tostring(lua_State* L) {
    HSMQTTClient *client = (__bridge HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));
    lua_pushstring(L, [[NSString stringWithFormat:@"%s: %@ (%p)",
                      USERDATA_TAG,
                      client.manager.host,
                      lua_topointer(L, 1)] UTF8String]);
    return 1;
}

static int userdata_gc(lua_State* L) {
    HSMQTTClient *client = (__bridge_transfer HSMQTTClient*)(*(void**)luaL_checkudata(L, 1, USERDATA_TAG));

    // Publish will message before cleanup if configured to do so
    if (client.publishWillOnDisconnect && client.willTopic && client.willMessage) {
        NSData *willData = [client.willMessage dataUsingEncoding:NSUTF8StringEncoding];
        UInt16 msgId = [client.manager sendData:willData
                                          topic:client.willTopic
                                            qos:client.willQoS
                                         retain:client.willRetain];

        // Only sleep for QoS 0 (fire and forget)
        // For QoS 1/2, the framework should handle acknowledgment
        if (client.willQoS == MQTTQosLevelAtMostOnce) {
            [NSThread sleepForTimeInterval:0.1];
        } else {
            // For QoS 1/2, wait for delivery callback with timeout
            client.willMessageId = msgId;
            client.pendingDisconnect = YES;

            // Wait up to 2 seconds for delivery
            NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:2.0];
            while (client.pendingDisconnect && [timeout timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
    }

    // Clear delegate before disconnecting to prevent callbacks during cleanup
    client.manager.delegate = nil;
    [client.manager disconnectWithDisconnectHandler:nil];

    LuaSkin *skin = [LuaSkin sharedWithState:L];
    client.messageCallbackRef = [skin luaUnref:refTable ref:client.messageCallbackRef];
    client.stateCallbackRef = [skin luaUnref:refTable ref:client.stateCallbackRef];

    client = nil;
    return 0;
}

#pragma mark - Module Tables

static const luaL_Reg userdata_metaLib[] = {
    {"connect",            mqtt_connect},
    {"disconnect",         mqtt_disconnect},
    {"publish",            mqtt_publish},
    {"subscribe",          mqtt_subscribe},
    {"unsubscribe",        mqtt_unsubscribe},
    {"setMessageCallback", mqtt_setMessageCallback},
    {"setStateCallback",   mqtt_setStateCallback},
    {"state",              mqtt_state},
    {"__tostring",         userdata_tostring},
    {"__gc",               userdata_gc},
    {NULL,                 NULL}
};

static luaL_Reg moduleLib[] = {
    {"new", mqtt_new},
    {NULL,  NULL}
};

#pragma mark - Lua Module Initialization

int luaopen_hs__dtc_mqtt_internal(lua_State* L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    refTable = [skin registerLibraryWithObject:USERDATA_TAG
                                     functions:moduleLib
                                 metaFunctions:nil
                               objectFunctions:userdata_metaLib];

    return 1;
}
