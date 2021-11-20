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

	string homeserver, user_id, accessToken;
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

	void login(string user, string password)
	{
		string url = buildUrl("login");
		JSONValue req = JSONValue();
		req["type"] = "m.login.password";
		req["user"] = user;
		req["password"] = password;

		JSONValue resp = post(url, req);

		this.accessToken = resp["access_token"].str;
		this.user_id = resp["user_id"].str;
	}

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

	void joinRoom(string roomId, JSONValue thirdPartySigned = JSONValue())
	{
		// Why the hell are there 2 endpoints that do the *exact* same thing 
		string url = buildUrl("join/%s".format(translateRoomId(roomId)));

		post(url);
	}

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
								switch (ev["type"].str)
								{
									// New message
								case "m.room.message":
									auto content = ev["content"];
									if (!("msgtype" in content))
										break;
									string msgtype = ev["content"]["msgtype"].str;
									switch (msgtype)
									{
									case "m.text":
									case "m.notice":
										if (messageDelegate)
										{
											MatrixTextMessage text = new MatrixTextMessage();

											text.roomId = roomId;
											text.type = msgtype;
											text.age = ev["unsigned"]["age"].integer;
											text.author = ev["sender"].str;
											text.eventId = ev["event_id"].str;

											if ("body" in content)
												text.conent = content["body"].str;
											if ("format" in content)
												text.format = content["format"].str;
											if ("formatted_body" in content)
												text.formattedContent
													= content["formatted_body"].str;

											messageDelegate(text);
										}
										break;

										// TODO
									default:
									case "m.file":
									case "m.image":
									case "m.audio":
									case "m.video":
										if (messageDelegate)
										{
											MatrixMessage msg = new MatrixMessage();

											msg.roomId = roomId;
											msg.type = msgtype;
											msg.age = ev["unsigned"]["age"].integer;
											msg.author = ev["sender"].str;
											msg.eventId = ev["event_id"].str;

											messageDelegate(msg);
										}
									}

									break;
									// Membership change
								case "m.room.member":
									break;
								default:
									break;
								}
							}
						}
					}
				}
			}
		}
	}

	void markRead(string roomId, string eventId)
	{
		string url = buildUrl("rooms/%s/read_markers".format(translateRoomId(roomId)));

		JSONValue req = JSONValue();
		req["m.fully_read"] = eventId;
		req["m.read"] = eventId;

		post(url, req);
	}

	void delegate(MatrixMessage) messageDelegate;
	void delegate(string, string) inviteDelegate;

	void sendHTML(string roomId, string html, string fallback = null)
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(translateRoomId(roomId),
				transactionId));

		if(!fallback) fallback = html;
		JSONValue req = JSONValue();
		req["msgtype"] = getTextMessageType();
		req["format"] = "org.matrix.custom.html";
		req["formatted_body"] = html;
		req["body"] = html;

		put(url, req);

		transactionId++;
	}

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

	void sendImage(string roomId, string filename, string mxc)
	{
		sendFile(roomId, "m.image", filename, mxc);
	}

	string uploadFile(const void[] data, string filename, string mimetype)
	{
		string[string] params = ["filename" : filename];
		string url = buildUrl("upload", params, "r0", "media");

		// TODO: Ratelimits
		HTTP http = HTTP();
		http.postData(data);
		http.addRequestHeader("Content-Type", mimetype);
		JSONValue resp = makeHttpRequest!("POST")(url, JSONValue(), http);

		return resp["content_uri"].str;
	}

	string resolveRoomAlias(string roomalias)
	{
		string url = buildUrl("directory/room/%s".format(translate(roomalias,
				['#': "%23", ':': "%3A"])));

		JSONValue resp = get(url);

		return resp["room_id"].str;
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

class MatrixMessage
{
	string author, type, roomId, eventId;
	long age;
}

class MatrixTextMessage : MatrixMessage
{
	string conent, format, formattedContent;
}
