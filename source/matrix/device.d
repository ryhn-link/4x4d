module matrix.device;

import matrix;
import std.json;
import std.format;

/// Get information about all devices for current user
MatrixDeviceInfo[] getDevices(MatrixClient c)
{
	string url = c.buildUrl("devices");
	JSONValue ret = c.get(url);

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
MatrixDeviceInfo getDeviceInfo(MatrixClient c, string device_id)
{
	string url = c.buildUrl("devices/%s".format(device_id));
	JSONValue ret = c.get(url);

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
void setDeviceName(MatrixClient c, string name, string device_id = null)
{
	if (!device_id)
		device_id = c.deviceId;

	string url = c.buildUrl("devices/%s".format(device_id));

	JSONValue req = JSONValue();
	req["display_name"] = name;

	c.put(url, req);
}

/// Deletes devices, uses a password for authentication
/// NOTE: This will only work if the homeserver requires ONLY a password authentication
void deleteDevicesUsingPassword(MatrixClient c, string[] devices, string password)
{
	string url = c.buildUrl("delete_devices");

	string session;
	JSONValue noauthresp;

	// This is gonna reply with 401 and give us the session
	try
	{
		// Freezes here :/
		noauthresp = c.post(url);
	}
	catch (MatrixException e)
	{
		noauthresp = e.json;
	}

	session = noauthresp["session"].str;

	JSONValue req = JSONValue();
	req["auth"] = JSONValue();
	req["auth"]["session"] = session;
	req["auth"]["type"] = "m.login.password";
	req["auth"]["user"] = c.userId;
	req["auth"]["identifier"] = JSONValue();
	req["auth"]["identifier"]["type"] = "m.id.user";
	req["auth"]["identifier"]["user"] = c.userId;
	req["auth"]["password"] = password;
	req["devices"] = devices;

	c.post(url, req);
}
