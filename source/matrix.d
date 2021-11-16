module matrix;
import std.json;
import std.net.curl;
import std.format : format;

class MatrixClient
{
private:
	static const string[string] NULL_PARAMS;

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
}
