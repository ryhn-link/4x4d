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

	JSONValue makeHttpRequest(string method)(string url, JSONValue data = JSONValue())
	{
		HTTP http = HTTP(url);
		JSONValue returnbody;
		string returnstr = "";

		static if (method == "GET")
			http.method(HTTP.Method.get);
		else static if (method == "POST")
			http.method(HTTP.Method.post);
		else static if (method == "PUT")
			http.method(HTTP.Method.put);
		else static if (method == "DELETE")
			http.method(HTTP.Method.del);

		//import std.stdio;
		//writeln(method ~ " " ~ url);
		//writeln(data.toString);

		http.postData(data.toString);
		http.onReceive = (ubyte[] data) {
			returnstr ~= cast(string) data;
			return data.length;
		};
		CurlCode c = http.perform(ThrowOnError.no);
		returnbody = parseJSON(returnstr);
		//writeln(c);
		//writeln(returnstr);
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
		return makeHttpRequest!("PUT")(url, data);
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
			params["next_batch"] = nextBatch;

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

			if ("content" in rooms)
			{

			}
		}
	}

	void delegate(string) messageDelegate;
	void delegate(string, string) inviteDelegate;

	void sendHTML(string roomId, string html)
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(translateRoomId(roomId), transactionId));

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
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(translateRoomId(roomId), transactionId));

		JSONValue req = JSONValue();
		req["msgtype"] = getTextMessageType();
		req["body"] = text;

		put(url, req);

		transactionId++;
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
