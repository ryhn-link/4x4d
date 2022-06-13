module matrix.synapse;

import matrix;
import matrix.utils;
import std.string;
import std.json;
import std.conv;
import std.array;
import std.algorithm.iteration : map;

// Synapse Admin API
// Only for accounts marked as admins running on Synapse or compatible
// https://github.com/matrix-org/synapse/blob/develop/docs/admin_api/user_admin_api.md

SynapseAccountList listAccounts(MatrixClient c, SynapseListAccountParams params)
{
	JSONValue json = new RequestBuilder(c.buildUrl("users", "admin", "_synapse", "v2"))
		.setParameter("from", params.from)
		.setParameter("limit", params.count)
		.setParameter("guests", params.guests)
		.setParameter("deactivated", params.deactivated)
		.setParameter("order_by", params.orderBy)
		.setParameter("dir", params.direction)
		.setParameter("name", params.name)
		.setParameter("user_id", params.userId)
		.addAuth(c)
		.mxGet();

	SynapseAccountList list;
	list.total = json["total"].integer;
	if ("next_token" in json)
		list.nextToken = json["next_token"].str;

	foreach (j; json["users"].array)
	{
		auto acc = SynapseAccount();
		acc.isGuest = j["is_guest"].integer > 0;
		acc.isAdmin = j["admin"].integer > 0;
		acc.isDeactivated = j["deactivated"].integer > 0;
		acc.isShadowBanned = j["shadow_banned"].boolean;
		if (j["name"].type != JSONType.null_)
			acc.name = j["name"].str;
		if (j["avatar_url"].type != JSONType.null_)
			acc.avatarUrl = j["avatar_url"].str;
		if (j["user_type"].type != JSONType.null_)
			acc.userType = j["user_type"].str;
		acc.displayName = j["displayname"].str;
		acc.creationTimestamp = j["creation_ts"].integer;

		list.accounts ~= acc;
	}

	return list;
}

SynapseAccount getAccount(MatrixClient c, UserID user)
{
	JSONValue j = new RequestBuilder(
		c.buildUrl("users/%s".format(urlEncode(user)), "admin", "_synapse", "v2"))
		.addAuth(c)
		.mxGet();

	auto acc = SynapseAccount();
	acc.isGuest = j["is_guest"].integer > 0;
	acc.isAdmin = j["admin"].integer > 0;
	acc.isDeactivated = j["deactivated"].integer > 0;
	acc.isShadowBanned = j["shadow_banned"].boolean;
	if (j["name"].type != JSONType.null_)
		acc.name = j["name"].str;
	if (j["avatar_url"].type != JSONType.null_)
		acc.avatarUrl = j["avatar_url"].str;
	if (j["user_type"].type != JSONType.null_)
		acc.userType = j["user_type"].str;
	acc.displayName = j["displayname"].str;
	acc.creationTimestamp = j["creation_ts"].integer;

	if (j["appservice_id"].type != JSON_TYPE.null_)
		acc.appserviceId = j["appservice_id"].str;
	if (j["consent_server_notice_sent"].type != JSON_TYPE.null_)
		acc.consentServerNoticeSent = j["consent_server_notice_sent"].str;
	if (j["consent_version"].type != JSON_TYPE.null_)
		acc.consentVersion = j["consent_version"].str;

	foreach (tpid; j["threepids"].array)
	{
		auto threepid = SynapseAccount.ThreePID();
		threepid.medium = tpid["medium"].str;
		threepid.address = tpid["address"].str;
		threepid.addedAt = tpid["added_at"].integer;
		threepid.validatedAt = tpid["validated_at"].integer;

		acc.threePIDs ~= threepid;
	}

	foreach (exid; j["external_ids"].array)
	{
		auto externalid = SynapseAccount.ExternalId();
		externalid.authProvider = exid["auth_provider"].str;
		externalid.externalId = exid["external_id"].str;

		acc.externalIds ~= externalid;
	}

	return acc;
}

// Returns true if the account was created, false if an existing account was modified
bool createOrModifyAccount(MatrixClient c, UserID user, JSONValue json)
{
	auto resp = new RequestBuilder(
		c.buildUrl("users/%s".format(urlEncode(user)), "admin", "_synapse", "v2"))
		.addAuth(c)
		.put(json.toString, "application/json");

	// Handling errors
	mxParseResponse(resp);

	return resp.code == 201;
}

void deactivateAccount(MatrixClient c, UserID user, bool erase = false)
{
	JSONValue json = JSONValue();
	json["erase"] = erase;

	new RequestBuilder(
		c.buildUrl("deactivate/%s".format(urlEncode(user)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxPost(json);
}

void resetPassword(MatrixClient c, UserID user, string newPassword, bool logoutDevices = true)
{
	JSONValue json = JSONValue();
	json["new_password"] = newPassword;
	json["logout_devices"] = logoutDevices;

	new RequestBuilder(
		c.buildUrl("reset_password/%s".format(urlEncode(user)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxPost(json);
}

bool isAdmin(MatrixClient c, UserID user)
{
	JSONValue json = new RequestBuilder(
		c.buildUrl("admin/%s".format(urlEncode(user)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxGet();

	return json["admin"].boolean;
}

void setAdmin(MatrixClient c, UserID user, bool admin)
{
	JSONValue json = JSONValue();
	json["admin"] = admin;

	new RequestBuilder(
		c.buildUrl("admin/%s".format(urlEncode(user)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxPut(json);
}

// List the rooms a user is in
RoomID[] listUserRooms(MatrixClient c, UserID user)
{
	JSONValue json = new RequestBuilder(
		c.buildUrl(
			"users/%s/joined_rooms".format(urlEncode(user)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxGet();

	return json["joined_rooms"].array.map!((JSONValue j) => RoomID(j.str)).array;
}

// Gets an access token for a user
// Does not create a device, cannot be expired/logged out by user
string loginAs(MatrixClient c, UserID u)
{
	JSONValue json = new RequestBuilder(
		c.buildUrl("users/%s/login".format(urlEncode(u)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxPost(JSONValue());

	return json["access_token"].str;
}

void shadowban(MatrixClient c, UserID u)
{
	new RequestBuilder(c.buildUrl("users/%s/shadow_ban".format(urlEncode(u)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxPost(JSONValue());
}

void unshadowban(MatrixClient c, UserID u)
{
	new RequestBuilder(c.buildUrl("users/%s/shadow_ban".format(urlEncode(u)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxDelete();
}

RateLimit getRateLimits(MatrixClient c, UserID u)
{
	JSONValue json = new RequestBuilder(
		c.buildUrl(
			"users/%s/override_ratelimit".format(urlEncode(u)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxGet();

	return RateLimit(json["messages_per_second"].integer, json["burst_count"].integer);
}

void setRateLimits(MatrixClient c, UserID u, RateLimit limits)
{
	JSONValue json = JSONValue();
	json["messages_per_second"] = limits.messagesPerSecond;
	json["burst_count"] = limits.burstCount;

	new RequestBuilder(c.buildUrl("users/%s/override_ratelimit".format(urlEncode(u)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxPost(json);
}

void deleteRateLimits(MatrixClient c, UserID u)
{
	new RequestBuilder(c.buildUrl("users/%s/override_ratelimit".format(urlEncode(u)), "admin", "_synapse", "v1"))
		.addAuth(c)
		.mxDelete();
}

// Checks if localpart is available, regardless or registration status
bool usernameAvailable(MatrixClient c, string localpart)
{
	JSONValue json = new RequestBuilder(
		c.buildUrl(
			"username_available", "admin", "_synapse", "v1"))
		.setParameter("username", localpart)
		.addAuth(c)
		.mxGet();

	return json["available"].boolean;
}

struct RateLimit
{
	long messagesPerSecond = 0, burstCount = 0;
}

struct SynapseAccount
{
	// Set when listing accounts
	UserID name;
	MXC avatarUrl;
	string displayName, userType;
	bool isGuest, isAdmin, isDeactivated, isShadowBanned;
	ulong creationTimestamp;

	// Only set when getting account details
	string appserviceId, consentServerNoticeSent, consentVersion;
	ExternalId[] externalIds;
	ThreePID[] threePIDs;

	struct ExternalId
	{
		string authProvider, externalId;
	}

	struct ThreePID
	{
		string medium, address;
		long addedAt, validatedAt;
	}
}

struct SynapseAccountList
{
	SynapseAccount[] accounts;
	long total;
	string nextToken;
}

struct SynapseListAccountParams
{
	long from = 0, count = 100;
	bool guests = true, deactivated = false;
	string name, userId;
	OrderBy orderBy = OrderBy.name;
	Direction direction = Direction.Backwards;

	enum OrderBy
	{
		name = "name",
		is_guest = "is_guest",
		admin = "admin",
		user_type = "user_type",
		deactivated = "deactivated",
		shadow_banned = "shadow_banned",
		displayname = "displayname",
		avatar_url = "avatar_url",
		creation_ts = "creation_ts"
	}

	enum Direction
	{
		Forwards = "f",
		Backwards = "b"
	}
}
