module matrix;
import std.json;
import std.net.curl;
import std.format : format;
import std.string;

class MatrixClient
{
private:
	static const string[string] NULL_PARAMS;

	uint transactionId;
	string accessToken;

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
		if (paramString.length) url ~= paramString;

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

public:
	string homeserver, user_id;

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

		string reqs = req.toString();

		JSONValue resp = parseJSON(post(url, reqs));
		
		this.accessToken = resp["access_token"].str;
		this.user_id = resp["user_id"].str;
	}

	string[] getJoinedRooms()
	{
		string url = buildUrl("joined_rooms");

		JSONValue result = parseJSON(get(url));
		
		// TODO: Find a better way to do this 💀
		string[] rooms = [];
		foreach (r; result["joined_rooms"].array)
		{
			rooms ~= r.str;
		}
		return rooms;
	}

	void sync()
	{

	}

	void sendHTML(string roomId, string html)
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(roomId, transactionId));
		
		JSONValue req = JSONValue();
		req["msgtype"] = "m.text";
		req["format"] = "org.matrix.custom.html";
		req["formatted_body"] = html;
		req["body"] = html;

		string reqs = req.toString();

		JSONValue resp = parseJSON(put(url, reqs));

		transactionId++;
	}

	void sendString(string roomId, string text)
	{
		string url = buildUrl("rooms/%s/send/m.room.message/%d".format(roomId, transactionId));
		
		JSONValue req = JSONValue();
		req["msgtype"] = "m.text";
		req["body"] = text;

		string reqs = req.toString();

		JSONValue resp = parseJSON(put(url, reqs));

		transactionId++;
	}

	string resolveRoomAlias(string roomalias)
	{
		string url = buildUrl("directory/room/%s".format(
			translate(roomalias, [
					'#': "%23",
					':': "%3A"
					]
		)));

		JSONValue resp = parseJSON(get(url));

		return resp["room_id"].str;
	}
}
