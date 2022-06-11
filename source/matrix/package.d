module matrix;
import std.json;
import std.format : format;
import std.string;
import std.net.curl : HTTP, CurlCode, ThrowOnError;
import std.conv;
import std.range;
import std.regex;

public import matrix.mxc;
public import matrix.cif;

class MatrixClient
{
	string homeserver, accessToken, deviceId;
	UserID userId;

	uint transactionId;
	string nextBatch;

private:
	static const string[string] NULL_PARAMS;
public:

	string buildUrl(string endpoint, const string[string] params = NULL_PARAMS,
		string apiVersion = "unstable", string section = "client", bool auth = true)
	{
		string url = "%s/_matrix/%s/%s/%s".format(this.homeserver, section, apiVersion, endpoint);
		char concat = '?';

		if (auth && this.accessToken.length)
		{
			url ~= "%caccess_token=%s".format(concat, this.accessToken);
			concat = '&';
		}

		string paramString = this.makeParamString(params, concat);
		if (paramString.length)
			url ~= paramString;

		return url;
	}

	string makeParamString(const string[string] params, char concat)
	{
		if (params.length == 0)
		{
			return "";
		}
		string result = "%s".format(concat);
		foreach (key, value; params)
		{
			result ~= "%s=%s&".format(key, value);
		}
		return result[0 .. $ - 1];
	}

	string translateRoomId(string roomId)
	{
		return translate(roomId, ['#': "%23", ':': "%3A"]);
	}

	JSONValue makeHttpRequest(string method)(string url,
		JSONValue data = JSONValue(), HTTP http = HTTP())
	{
		http.url(url);
		JSONValue returnbody;
		string returnstr = "";

		static if (method == "GET")
			http.method(HTTP.Method.get);
		else static if (method == "POST")
			http.method(HTTP.Method.post);
		else static if (method == "PUT")
		{
			// Using the HTTP struct with PUT seems to hang, don't use it
			http.method(HTTP.Method.put);
		}
		else static if (method == "DELETE")
			http.method(HTTP.Method.del);
		else static if (method == "OPTIONS")
			http.method(HTTP.Method.options);

		if (!data.isNull)
			http.postData(data.toString);
		http.onReceive = (ubyte[] data) {
			returnstr ~= cast(string) data;
			return data.length;
		};
		CurlCode c = http.perform(ThrowOnError.no);
		returnbody = parseJSON(returnstr);
		if (c)
		{
			throw new MatrixException(c, returnbody);
		}
		return returnbody;
	}

	JSONValue get(string url, JSONValue data = JSONValue())
	{
		return makeHttpRequest!("GET")(url, data);
	}

	JSONValue post(string url, JSONValue data = JSONValue())
	{
		return makeHttpRequest!("POST")(url, data);
	}

	JSONValue put(string url, JSONValue data = JSONValue())
	{
		// Using the HTTP struct with PUT seems to hang
		// return makeHttpRequest!("PUT")(url, data);

		// std.net.curl.put works fine
		import std.net.curl : cput = put;

		return parseJSON(cput(url, data.toString()));
	}

	JSONValue options(string url, JSONValue data = JSONValue())
	{
		return makeHttpRequest!("OPTIONS")(url, data);
	}

	/// Should sync() keep the JSONValue reference 
	bool syncKeepJSONEventReference = false;

	this(string homeserver = "https://matrix.org")
	{
		this.homeserver = homeserver;
		// Check well known matrix
	}

	/// Log in to the matrix server using a username and password.
	/// deviceId is optional, if none provided, server will generate it's own
	/// If provided, server will invalidate the previous access token for this device
	void passwordLogin(string user, string password, string device_id = null)
	{
		string url = buildUrl("login");
		JSONValue req = JSONValue();
		req["type"] = "m.login.password";
		req["user"] = user;
		req["password"] = password;
		if (device_id)
			req["device_id"] = device_id;

		JSONValue resp = post(url, req);

		this.accessToken = resp["access_token"].str;
		this.userId = resp["user_id"].str;
		this.deviceId = resp["device_id"].str;
	}

	/// Log in to the matrix server using an existing access token assigned to a device_id.
	void tokenLogin(string access_token, string device_id)
	{
		this.accessToken = access_token;
		this.deviceId = device_id;

		string url = buildUrl("account/whoami");
		JSONValue ret = get(url);

		userId = ret["user_id"].str;
		deviceId = ret["device_id"].str;
	}

	/// ditto
	RoomID[] getJoinedRooms()
	{
		string url = buildUrl("joined_rooms");

		JSONValue result = get(url);

		import std.algorithm.iteration;

		return result["joined_rooms"].array.map!((JSONValue j) => RoomID(j.str)).array;
	}

	/// Joins a room by it's room id or alias, retuns it's room id
	RoomID joinRoom(T)(T room) if (isSomeRoomID!T)
	{
		// Why the hell are there 2 endpoints that do the *exact* same thing 
		string url = buildUrl("join/%s".format(translateRoomId(room)));

		JSONValue ret = post(url);
		return RoomID(ret["room_id"].str);
	}

	/// Fetch new events
	void sync()
	{
		import std.stdio;

		string[string] params;
		if (nextBatch)
			params["since"] = nextBatch;

		string url = buildUrl("sync", params);

		JSONValue response = get(url);

		nextBatch = response["next_batch"].str;
		if ("rooms" in response)
		{
			JSONValue rooms = response["rooms"];

			if ("invite" in rooms)
			{
				JSONValue invites = rooms["invite"];

				// I hate JSON dictionaries
				foreach (inv; invites.object.keys)
				{
					if (inviteDelegate)
						inviteDelegate(RoomID(inv), invites[inv]["invite_state"]["events"][0]["sender"]
								.str);
				}

			}

			if ("join" in rooms)
			{
				foreach (roomId; rooms["join"].object.keys)
				{
					if ("timeline" in rooms["join"][roomId])
					{
						if ("events" in rooms["join"][roomId]["timeline"])
						{
							foreach (ev; rooms["join"][roomId]["timeline"]["events"].array)
							{
								MatrixEvent e = parseEvent(ev, syncKeepJSONEventReference, roomId);
								if (eventDelegate)
									eventDelegate(e);
							}
						}
					}
				}
			}
		}
	}

	/// Parses an event from a JSONValue, use casting or the type field to determine it's type. 
	/// keepJSONReference determines if the JSONValue should be kept in the MatrixEvent object. 
	/// You can override this function in your program if you need support for more event types. 
	MatrixEvent parseEvent(JSONValue ev, bool keepJSONReference = false, string optRoomId = null)
	{
		MatrixEvent e;

		switch (ev["type"].str)
		{
			// New message
		case "m.room.message":
			JSONValue content = ev["content"];
			if (!("msgtype" in content))
				break;
			string msgtype = ev["content"]["msgtype"].str;
			MatrixMessage msg;
			switch (msgtype)
			{
			case "m.text":
			case "m.notice":
			case "m.emote":
				MatrixTextMessage text = new MatrixTextMessage();

				if ("format" in content)
					text.format = content["format"].str;
				if ("formatted_body" in content)
					text.formattedContent
						= content["formatted_body"].str;

				msg = text;
				break;
				// TODO
			default:
			case "m.file":
			case "m.image":
			case "m.audio":
			case "m.video":
			case "m.location":
				msg = new MatrixMessage();
				break;
			}

			msg.msgtype = msgtype;
			if ("body" in content)
				msg.content = content["body"].str;
			e = msg;
			break;

			// Emoji reaction to a message
		case "m.reaction":
			MatrixReaction r = new MatrixReaction();

			JSONValue relatesTo = ev["content"]["m.relates_to"];
			r.emoji = relatesTo["key"].str;
			r.relatesToEvent = relatesTo["event_id"].str;
			r.relType = relatesTo["rel_type"].str;
			e = r;
			break;

		case "m.room.redaction":
			MatrixRedaction r = new MatrixRedaction();

			r.redacts = ev["redacts"].str;
			if ("reason" in ev["content"])
				r.reason = ev["content"]["reason"].str;
			e = r;
			break;
		
		default:
			break;
		}

		/// Common event properties
		if (e is null)
			e = new MatrixEvent();

		e.type = ev["type"].str;
		if ("room_id" in ev)
			e.roomId = ev["room_id"].str;
		else if (optRoomId)
			e.roomId = optRoomId;

		e.age = ev["unsigned"]["age"].integer;
		e.sender = ev["sender"].str;
		e.eventId = ev["event_id"].str;

		if (keepJSONReference)
			e.json = ev;

		return e;
	}

	/// Gets an event from a room by it's ID
	MatrixEvent getEvent(string room_id, string event_id, bool keepJSONReference = false)
	{
		string url = buildUrl("rooms/%s/context/%s".format(room_id, event_id));

		JSONValue req = JSONValue();
		req["limit"] = 1;

		JSONValue res = get(url, req);

		return parseEvent(res["event"], keepJSONReference, room_id);
	}

	/// Sets the position of the read marker for given room
	void markRead(T)(T room, EventID eventId) if(isSomeRoomID!T)
	{
		string url = buildUrl("rooms/%s/read_markers".format(translateRoomId(room)));

		JSONValue req = JSONValue();
		req["m.fully_read"] = eventId.toString;
		req["m.read"] = eventId.toString;

		post(url, req);
	}

	/// Called when a new message is received
	void delegate(MatrixEvent) eventDelegate;
	/// Called when a new invite is received
	void delegate(RoomID, string) inviteDelegate;

	/// Uploads a file to the server and returns the MXC URI
	MXC uploadFile(const void[] data, string filename, string mimetype)
	{
		string[string] params = ["filename": filename];
		string url = buildUrl("upload", params, "r0", "media");

		// TODO: Ratelimits
		HTTP http = HTTP();
		http.postData(data);
		http.addRequestHeader("Content-Type", mimetype);
		JSONValue resp = makeHttpRequest!("POST")(url, JSONValue(), http);

		return MXC(resp["content_uri"].str);
	}

	/// Used for downloading HTTP files, see MXC.getDownloadURL and MXC.getThumbnailURL
	/// to download MXC files 
	void[] downloadFile(string url, string mimeType = "*/*")
	{
		auto http = HTTP(url);
		http.method(HTTP.Method.get);
		http.addRequestHeader("Accept", mimeType);
		void[] ret;
		http.onReceive = (ubyte[] data) { ret ~= data; return data.length; };
		http.perform();

		return ret;
	}

	EventID sendEvent(T)(T room, string eventType, JSONValue json)
			if (isSomeRoomID!(T))
	{
		string url = buildUrl("rooms/%s/send/%s/%d".format(translateRoomId(room), eventType, transactionId));

		JSONValue ret = put(url, json);
		transactionId++;

		return EventID(ret["event_id"].str);
	}

	EventID redactEvent(T)(T room, EventID event, string reason = null)
	{
		string url = buildUrl("rooms/%s/redact/%s/%d".format(translateRoomId(room), event, transactionId));

		JSONValue json = JSONValue();
		if (reason)
			json["reason"] = reason;

		JSONValue ret = put(url, json);
		transactionId++;

		return EventID(ret["event_id"].str);
	}

	string[] getRoomMembers(string room_id)
	{
		string url = buildUrl("rooms/%s/joined_members".format(translateRoomId(room_id)));

		JSONValue res = get(url);

		return res["joined"].object.keys;
	}

	MatrixProfile getProfile(UserID user_id)
	{
		string url = buildUrl("profile/" ~ user_id);

		JSONValue res = get(url);

		MatrixProfile p = new MatrixProfile();

		if ("avatar_url" in res)
			p.avatar = res["avatar_url"].str;

		if ("displayname" in res)
			p.displayName = res["displayname"].str;

		return p;
	}

	RoomID createRoom(MatrixRoomPresetEnum preset = MatrixRoomPresetEnum.private_chat,
		bool showInDirectory = false, string roomAliasName = null, string name = null,
		bool is_direct = false, string[] inviteUsers = [])
	{
		string url = buildUrl("createRoom");

		JSONValue req = JSONValue();

		req["preset"] = preset;
		req["visibility"] = showInDirectory ? "public" : "private";

		if (name)
			req["name"] = name;
		if (roomAliasName)
			req["room_alias_name"] = roomAliasName;

		req["is_direct"] = is_direct;
		req["invite"] = inviteUsers;

		JSONValue res = post(url, req);
		import std.stdio;

		return RoomID(res["room_id"].str);
	}

	/// Resolves the room alias to a room id, no authentication required
	string resolveRoomAlias(string roomalias)
	{
		string url = buildUrl("directory/room/%s".format(translate(roomalias,
				['#': "%23", ':': "%3A"])));

		JSONValue resp = get(url);

		return resp["room_id"].str;
	}

	/// Sets your presence
	/// NOTE: No clients support status messages yet
	void setPresence(MatrixPresenceEnum presence, string status_msg = null)
	{
		string url = buildUrl("presence/%s/status".format(userId));

		JSONValue req;
		req["presence"] = presence;
		if (status_msg)
			req["status_msg"] = status_msg;
		else
			req["status_msg"] = "";

		put(url, req);
	}

	/// Gets the specified user's presence
	MatrixPresence getPresence(string userId = null)
	{
		if (!userId)
			userId = this.userId;

		string url = buildUrl("presence/%s/status".format(userId));

		JSONValue resp = get(url);
		import std.stdio;

		MatrixPresence p = new MatrixPresence();
		if ("currently_active" in resp)
			p.currentlyActive = resp["currently_active"].boolean;
		p.lastActiveAgo = resp["last_active_ago"].integer;
		p.presence = resp["presence"].str.to!MatrixPresenceEnum;
		if (!resp["status_msg"].isNull)
			p.statusMessage = resp["status_msg"].str;

		return p;
	}

	/// Gets custom account data with specified type
	JSONValue getAccountData(string type)
	{
		string url = buildUrl("user/%s/account_data/%s".format(userId, type));

		JSONValue resp = get(url);

		return resp;
	}

	/// Sets custom account data for specified type
	void setAccountData(string type, JSONValue data)
	{
		string url = buildUrl("user/%s/account_data/%s".format(userId, type));

		put(url, data);
	}

	/// Get custom account data with specified type for the given room
	/// NOTE: Room aliases don't have the same data as their resolved room ids
	JSONValue getRoomData(string room_id, string type)
	{
		string url = buildUrl("user/%s/rooms/%s/account_data/%s".format(userId,
				translateRoomId(room_id), type));

		JSONValue resp = get(url);

		return resp;
	}

	/// Set custom account data with specified type for the given room
	/// NOTE: Room aliases don't have the same data as their resolved room ids
	void setRoomData(string room_id, string type, JSONValue data)
	{
		string url = buildUrl("user/%s/rooms/%s/account_data/%s".format(userId,
				translateRoomId(room_id), type));

		put(url, data);
	}

	JSONValue getRoomState(T)(T room, string eventType, string stateKey = null)
			if (isSomeRoomID!T)
	{
		string url;
		if (stateKey)
			url = buildUrl("rooms/%s/state/%s/%s".format(translateRoomId(room), eventType, stateKey));
		else
			url = buildUrl("rooms/%s/state/%s".format(translateRoomId(room), eventType));

		JSONValue resp = get(url);

		return resp;
	}

	JSONValue getRoomStates(T)(T room) if (isSomeRoomID!T)
	{
		string url = buildUrl("rooms/%s/state".format(translateRoomId(room)));

		JSONValue resp = get(url);

		return resp;
	}

	void setRoomState(T)(T room, JSONValue json, string eventType, string stateKey = null)
			if (isSomeRoomID!T)
	{
		string url;
		if (stateKey)
			url = buildUrl("rooms/%s/state/%s/%s".format(translateRoomId(room), eventType, stateKey));
		else
			url = buildUrl("rooms/%s/state/%s".format(translateRoomId(room), eventType));
		post(url, json);
	}
}

class MatrixException : Exception
{
	string errcode, error;
	int statuscode;
	JSONValue json;
	this(int statuscode, JSONValue json)
	{
		this.json = json;
		this.statuscode = statuscode;
		if ("errcode" in json)
			errcode = json["errcode"].str;
		if ("error" in json)
			error = json["error"].str;

		super(statuscode.to!string ~ " - " ~ errcode ~ ":" ~ error);
	}
}

class MatrixEvent
{
	string sender, roomId, type;
	EventID eventId;
	long age;
	JSONValue json;
}

class MatrixReaction : MatrixEvent
{
	string relType, relatesToEvent, emoji;
}

class MatrixMessage : MatrixEvent
{
	string msgtype, content;
}

class MatrixTextMessage : MatrixMessage
{
	string format, formattedContent;
}

class MatrixRedaction : MatrixEvent
{
	EventID redacts;
	string reason;
}

class MatrixDeviceInfo
{
	string deviceId, displayName, lastSeenIP;
	long lastSeen;
}

class MatrixPresence
{
	bool currentlyActive;
	long lastActiveAgo;
	MatrixPresenceEnum presence;
	string statusMessage;
}

enum MatrixRoomPresetEnum : string
{
	private_chat = "private_chat",
	public_chat = "public_chat",
	trusted_private_chat = "trusted_private_chat"
}

enum MatrixPresenceEnum : string
{
	online = "online",
	offline = "offline",
	unavailable = "unavailable"
}

class MatrixProfile
{
	string displayName;
	MXC avatar;
}
