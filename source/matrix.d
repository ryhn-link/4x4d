module matrix;
import std.json;
import std.format : format;
import std.string;
import std.net.curl : HTTP, CurlCode, ThrowOnError;
import std.conv;
import std.range;

class MatrixClient
{
private:
	static const string[string] NULL_PARAMS;
public:
	uint transactionId;
	string nextBatch;

	string buildUrl(string endpoint, const string[string] params = NULL_PARAMS,
		string apiVersion = "unstable", string section = "client")
	{
		string url = "%s/_matrix/%s/%s/%s".format(this.homeserver, section, apiVersion, endpoint);
		char concat = '?';

		if (this.accessToken.length)
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

		//import std.stdio;
		//writeln(method ~ " " ~ url);
		//writeln(data.toString);

		if (!data.isNull)
			http.postData(data.toString);
		http.onReceive = (ubyte[] data) {
			returnstr ~= cast(string) data;
			return data.length;
		};
		//http.verbose(true);
		CurlCode c = http.perform(ThrowOnError.no);
		//writeln(c);
		//writeln(returnstr);
		returnbody = parseJSON(returnstr);
		if (c)
		{
			throw new MatrixException(c, returnbody);
		}
		return returnbody;
	}

	JSONValue get(string url)
	{
		return makeHttpRequest!("GET")(url);
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

	string homeserver, userId, accessToken, deviceId;
	bool useNotice = true;

	string getTextMessageType()
	{
		return useNotice ? "m.notice" : "m.text";
	}

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

	/// Get information about all devices for current user
	MatrixDeviceInfo[] getDevices()
	{
		string url = buildUrl("devices");
		JSONValue ret = get(url);

		MatrixDeviceInfo[] inf;
		foreach (d; ret["devices"].array)
		{
			MatrixDeviceInfo i = new MatrixDeviceInfo();
			i.deviceId = d["device_id"].str;
			if (!d["display_name"].isNull)
				i.displayName = d["display_name"].str;
			if (!d["last_seen_ip"].isNull)
				i.lastSeenIP = d["last_seen_ip"].str;
			if (!d["last_seen_ts"].isNull)
				i.lastSeen = d["last_seen_ts"].integer;

			inf ~= i;
		}

		return inf;
	}

	/// Get information for a single device by it's device id
	MatrixDeviceInfo getDeviceInfo(string device_id)
	{
		string url = buildUrl("devices/%s".format(device_id));
		JSONValue ret = get(url);

		MatrixDeviceInfo i = new MatrixDeviceInfo();
		i.deviceId = ret["device_id"].str;
		if (!ret["display_name"].isNull)
			i.displayName = ret["display_name"].str;
		if (!ret["last_seen_ip"].isNull)
			i.lastSeenIP = ret["last_seen_ip"].str;
		if (!ret["last_seen_ts"].isNull)
			i.lastSeen = ret["last_seen_ts"].integer;

		return i;
	}

	/// Updates the display name for a device
	/// device_id is optional, if null, current device ID will be used
	void setDeviceName(string name, string device_id = null)
	{
		if (!device_id)
			device_id = deviceId;

		string url = buildUrl("devices/%s".format(device_id));

		JSONValue req = JSONValue();
		req["display_name"] = name;

		put(url, req);
	}

	/// ditto
	string[] getJoinedRooms()
	{
		string url = buildUrl("joined_rooms");

		JSONValue result = get(url);

		// TODO: Find a better way to do this 💀
		string[] rooms = [];
		foreach (r; result["joined_rooms"].array)
		{
			rooms ~= r.str;
		}
		return rooms;
	}

	/// Joins a room by it's room id or alias, retuns it's room id
	string joinRoom(string roomId)
	{
		// Why the hell are there 2 endpoints that do the *exact* same thing 
		string url = buildUrl("join/%s".format(translateRoomId(roomId)));

		JSONValue ret = post(url);
		return ret["room_id"].str;
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
						inviteDelegate(inv, invites[inv]["invite_state"]["events"][0]["sender"].str);
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

								case "m.reaction":
									MatrixReaction r = new MatrixReaction();

									JSONValue relatesTo = ev["content"]["m.relates_to"];
									r.emoji = relatesTo["key"].str;
									r.relatesToEvent = relatesTo["event_id"].str;
									r.relType = relatesTo["rel_type"].str;
									e = r;
									break;

									// Unknown events
								default:
								case "m.room.member":
									e = new MatrixEvent();
									break;
								}
								/// Common event properties

								e.type = ev["type"].str;
								e.roomId = roomId;
								e.age = ev["unsigned"]["age"].integer;
								e.sender = ev["sender"].str;
								e.eventId = ev["event_id"].str;

								if(eventDelegate)
									eventDelegate(e);
							}
						}
					}
				}
			}
		}
	}

	/// Sets the position of the read marker for given room
	void markRead(string roomId, string eventId)
	{
		string url = buildUrl("rooms/%s/read_markers".format(translateRoomId(roomId)));

		JSONValue req = JSONValue();
		req["m.fully_read"] = eventId;
		req["m.read"] = eventId;

		post(url, req);
	}

	/// Called when a new message is received
	void delegate(MatrixEvent) eventDelegate;
	/// Called when a new invite is received
	void delegate(string, string) inviteDelegate;

	/// Sends a m.room.message with format of org.matrix.custom.html
	/// fallback is the plain text version of html if the client doesn't support html
	void sendHTML(string roomId, string html, string fallback = null)
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(translateRoomId(roomId),
				transactionId));

		if (!fallback)
			fallback = html;
		JSONValue req = JSONValue();
		req["msgtype"] = getTextMessageType();
		req["format"] = "org.matrix.custom.html";
		req["formatted_body"] = html;
		req["body"] = fallback;

		put(url, req);

		transactionId++;
	}

	/// Sends a m.room.message
	void sendString(string roomId, string text)
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(translateRoomId(roomId),
				transactionId));

		JSONValue req = JSONValue();
		req["msgtype"] = getTextMessageType();
		req["body"] = text;

		put(url, req);

		transactionId++;
	}

	/// Sends a m.room.message with specified msgtype and MXC URI
	void sendFile(string roomId, string filename, string mxc, string msgtype = "m.file")
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(translateRoomId(roomId),
				transactionId));

		JSONValue req = JSONValue();
		req["msgtype"] = msgtype;
		req["url"] = mxc;
		req["body"] = filename;

		put(url, req);

		transactionId++;
	}

	/// Sends a m.room.message with type of m.image with specified MXC URI
	void sendImage(string roomId, string filename, string mxc)
	{
		sendFile(roomId, "m.image", filename, mxc);
	}

	/// Uploads a file to the server and returns the MXC URI
	string uploadFile(const void[] data, string filename, string mimetype)
	{
		string[string] params = ["filename": filename];
		string url = buildUrl("upload", params, "r0", "media");

		// TODO: Ratelimits
		HTTP http = HTTP();
		http.postData(data);
		http.addRequestHeader("Content-Type", mimetype);
		JSONValue resp = makeHttpRequest!("POST")(url, JSONValue(), http);

		return resp["content_uri"].str;
	}

	void addReaction(string room_id, string event_id, string emoji)
	{
		string url = buildUrl("rooms/%s/send/m.reaction/%d".format(translateRoomId(room_id),
				transactionId));

		JSONValue req = JSONValue();
		req["m.relates_to"] = JSONValue();
		req["m.relates_to"]["rel_type"] = "m.annotation";
		req["m.relates_to"]["event_id"] = event_id;
		req["m.relates_to"]["key"] = emoji;

		put(url, req);

		transactionId++;
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

		writeln(resp);
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
	/// NOTE 2: Synapse doesn't seem to validate the room id, so you can put anything in place of it
	JSONValue getRoomData(string room_id, string type)
	{
		string url = buildUrl("user/%s/rooms/%s/account_data/%s".format(userId,
				translateRoomId(room_id), type));

		JSONValue resp = get(url);

		return resp;
	}

	/// Set custom account data with specified type for the given room
	/// NOTE: Room aliases don't have the same data as their resolved room ids
	/// NOTE 2: Synapse doesn't seem to validate the room id, so you can put anything in place of it
	void setRoomData(string room_id, string type, JSONValue data)
	{
		string url = buildUrl("user/%s/rooms/%s/account_data/%s".format(userId,
				translateRoomId(room_id), type));

		put(url, data);
	}
}

class MatrixException : Exception
{
	string errcode, error;
	int statuscode;
	this(int statuscode, JSONValue json)
	{
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
	string sender, roomId, eventId, type;
	long age;
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

class MatrixDeviceInfo
{
	string deviceId, displayName, lastSeenIP;
	// I have no idea how to convert UNIX timestamps to DateTime
	long lastSeen;
}

class MatrixPresence
{
	bool currentlyActive;
	long lastActiveAgo;
	MatrixPresenceEnum presence;
	string statusMessage;
}

enum MatrixPresenceEnum : string
{
	online = "online",
	offline = "offline",
	unavailable = "unavailable"
}
