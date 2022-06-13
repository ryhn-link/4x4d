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
import matrix.utils;

class MatrixClient
{
	string homeserver, accessToken, deviceId;
	UserID userId;

	uint transactionId;
	string nextBatch;

	string apiVersion = "v3";

private:
	static const string[string] NULL_PARAMS;
public:

	string buildUrl(string endpoint, string section = "client", string api = "_matrix", string versionOverride = null)
	{
		if(!versionOverride) versionOverride = apiVersion;
		return "%s/%s/%s/%s/%s".format(this.homeserver, api, section, versionOverride, endpoint);
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
		JSONValue req = JSONValue();
		req["type"] = "m.login.password";
		req["identifier"] = JSONValue();
		req["identifier"]["type"] = "m.id.user";
		req["identifier"]["user"] = user;
		req["password"] = password;
		if (device_id)
			req["device_id"] = device_id;

		JSONValue resp = new RequestBuilder(buildUrl("login"))
			.mxPost(req);

		this.accessToken = resp["access_token"].str;
		this.userId = resp["user_id"].str;
		this.deviceId = resp["device_id"].str;
	}

	/// Log in to the matrix server using an existing access token assigned to a device_id.
	void tokenLogin(string access_token, string device_id)
	{
		this.accessToken = access_token;
		this.deviceId = device_id;

		JSONValue ret = new RequestBuilder(buildUrl("account/whoami"))
			.addAuth(this)
			.mxGet();

		userId = ret["user_id"].str;
		deviceId = ret["device_id"].str;
	}

	/// ditto
	RoomID[] getJoinedRooms()
	{
		JSONValue result = new RequestBuilder(buildUrl("joined_rooms"))
			.addAuth(this)
			.mxGet();

		import std.algorithm.iteration;

		return result["joined_rooms"].array.map!((JSONValue j) => RoomID(j.str)).array;
	}

	/// Joins a room by it's room id or alias, retuns it's room id
	RoomID joinRoom(T)(T room) if (isSomeRoomID!T)
	{
		JSONValue ret = new RequestBuilder("join/%s".format(urlEncode(room)))
			.addAuth(this)
			.mxPost();

		return RoomID(ret["room_id"].str);
	}

	/// Fetch new events
	void sync()
	{
		import std.stdio;

		JSONValue response = new RequestBuilder(buildUrl("sync"))
			.setParameter("since", nextBatch)
			.addAuth(this)
			.mxGet();

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
		JSONValue res = new RequestBuilder(buildUrl("rooms/%s/context/%s"
				.format(urlEncode(room_id), urlEncode(event_id))))

			.addAuth(this)
			.setParameter("limit", 1)
			.mxGet();

		return parseEvent(res["event"], keepJSONReference, room_id);
	}

	/// Sets the position of the read marker for given room
	void markRead(T)(T room, EventID eventId) if (isSomeRoomID!T)
	{
		JSONValue req = JSONValue();
		req["m.fully_read"] = eventId.toString;
		req["m.read"] = eventId.toString;

		new RequestBuilder(buildUrl("rooms/%s/read_markers".format(urlEncode(room))))
			.addAuth(this)
			.mxPost(req);
	}

	/// Called when a new message is received
	void delegate(MatrixEvent) eventDelegate;
	/// Called when a new invite is received
	void delegate(RoomID, string) inviteDelegate;

	/// Uploads a file to the server and returns the MXC URI
	MXC uploadFile(ubyte[] data, string filename, string mimetype)
	{
		JSONValue resp = new RequestBuilder(buildUrl("upload", "media"))
			.addAuth(this)
			.setParameter("filename", filename)
			.mxPost(data, mimetype);

		return MXC(resp["content_uri"].str);
	}

	/// Used for downloading HTTP files, see MXC.getDownloadURL and MXC.getThumbnailURL
	/// to download MXC files 
	ubyte[] downloadFile(string url, string mimeType = "*/*")
	{
		auto resp = new RequestBuilder(url)
			.setHeader("Accept", mimeType)
			.get();

		return resp.responseBody.data;
	}

	EventID sendEvent(T)(T room, string eventType, JSONValue json)
			if (isSomeRoomID!(T))
	{
		JSONValue ret = new RequestBuilder(buildUrl("rooms/%s/send/%s/%d".format(urlEncode(room), eventType, transactionId)))
			.addAuth(this)
			.mxPost(json);

		transactionId++;
		return EventID(ret["event_id"].str);
	}

	EventID redactEvent(T)(T room, EventID event, string reason = null)
	{
		JSONValue json = JSONValue();
		if (reason)
			json["reason"] = reason;

		JSONValue ret =	new RequestBuilder(buildUrl("rooms/%s/redact/%s/%d".format(urlEncode(room), event, transactionId)))
			.addAuth(this)
			.mxPost(json);

		transactionId++;

		return EventID(ret["event_id"].str);
	}

	string[] getRoomMembers(string room_id)
	{
		JSONValue res = new RequestBuilder(buildUrl("rooms/%s/joined_members".format(urlEncode(room_id))))
			.addAuth(this)
			.mxGet();

		return res["joined"].object.keys;
	}

	MatrixProfile getProfile(UserID user_id)
	{
		JSONValue res = new RequestBuilder(buildUrl("profile/%s".format(urlEncode(user_id))))
			.mxGet();

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
		JSONValue req = JSONValue();

		req["preset"] = preset;
		req["visibility"] = showInDirectory ? "public" : "private";

		if (name)
			req["name"] = name;
		if (roomAliasName)
			req["room_alias_name"] = roomAliasName;

		req["is_direct"] = is_direct;
		req["invite"] = inviteUsers;

		JSONValue res = new RequestBuilder(buildUrl("createRoom"))
			.addAuth(this)
			.mxPost(req);

		return RoomID(res["room_id"].str);
	}

	/// Resolves the room alias to a room id, no authentication required
	string resolveRoomAlias(RoomAlias roomalias)
	{
		JSONValue resp = new RequestBuilder(buildUrl("directory/room/%s".format(urlEncode(roomalias))))
			.addAuth(this)
			.mxGet();

		return resp["room_id"].str;
	}

	/// Sets your presence
	/// NOTE: No clients support status messages yet
	void setPresence(MatrixPresenceEnum presence, string status_msg = null)
	{
		JSONValue req;
		req["presence"] = presence;
		if (status_msg)
			req["status_msg"] = status_msg;
		else
			req["status_msg"] = "";

		new RequestBuilder(buildUrl("presence/%s/status".format(urlEncode(userId))))
			.addAuth(this)
			.mxPost(req);
	}

	/// Gets the specified user's presence
	MatrixPresence getPresence(string userId = null)
	{
		if (!userId)
			userId = this.userId;

		JSONValue resp = new RequestBuilder(buildUrl("presence/%s/status".format(urlEncode(userId))))
			.addAuth(this)
			.mxGet();

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
		JSONValue resp = new RequestBuilder(buildUrl("user/%s/account_data/%s".format(urlEncode(userId), type)))
			.addAuth(this)
			.mxGet();

		return resp;
	}

	/// Sets custom account data for specified type
	void setAccountData(string type, JSONValue data)
	{
		new RequestBuilder(buildUrl("user/%s/account_data/%s".format(urlEncode(userId), type)))
			.addAuth(this)
			.mxPut(data);
	}

	/// Get custom account data with specified type for the given room
	/// NOTE: Room aliases don't have the same data as their resolved room ids
	JSONValue getRoomData(string room_id, string type)
	{
		JSONValue resp = new RequestBuilder("user/%s/rooms/%s/account_data/%s".format(urlEncode(userId),
				urlEncode(room_id), type))
				.addAuth(this)
				.mxGet();

		return resp;
	}

	/// Set custom account data with specified type for the given room
	/// NOTE: Room aliases don't have the same data as their resolved room ids
	void setRoomData(string room_id, string type, JSONValue data)
	{
		new RequestBuilder("user/%s/rooms/%s/account_data/%s".format(urlEncode(userId),
				urlEncode(room_id), type))
				.addAuth(this)
				.mxPut(data);
	}

	JSONValue getRoomState(T)(T room, string eventType, string stateKey = null)
			if (isSomeRoomID!T)
	{
		string url;
		if (stateKey)
			url = buildUrl("rooms/%s/state/%s/%s".format(urlEncode(room), eventType, stateKey));
		else
			url = buildUrl("rooms/%s/state/%s".format(urlEncode(room), eventType));
		
		JSONValue resp = new RequestBuilder(url)
			.addAuth(this)
			.mxGet();

		return resp;
	}

	JSONValue getRoomStates(T)(T room) if (isSomeRoomID!T)
	{
		JSONValue resp = new RequestBuilder("rooms/%s/state".format(urlEncode(room)))
			.addAuth(this)
			.mxGet();

		return resp;
	}

	void setRoomState(T)(T room, JSONValue json, string eventType, string stateKey = null)
			if (isSomeRoomID!T)
	{
		string url;
		if (stateKey)
			url = buildUrl("rooms/%s/state/%s/%s".format(urlEncode(room), eventType, stateKey));
		else
			url = buildUrl("rooms/%s/state/%s".format(urlEncode(room), eventType));

		new RequestBuilder(url)
			.addAuth(this)
			.mxPost(json);
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
