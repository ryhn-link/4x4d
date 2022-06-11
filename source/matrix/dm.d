module matrix.dm;

import matrix;
import std.json;
import std.range;

/// Gets the direct message room for given user. 
/// Returns null if the room doesn't exist
string getDirectMessageRoom(MatrixClient c, UserID user_id)
{
	string user = user_id;
	try
	{
		JSONValue result = c.getAccountData("m.direct");
		if ("content" in result)
		{
			if (user in result["content"])
			{
				return result["content"][user].array.front.str;
			}
		}
	}
	catch (Exception e)
	{
	}

	return null;
}

/// Creates the direct message room and stores it's ID in account data
RoomID createDirectMessageRoom(MatrixClient c, UserID user_id)
{
	/// Create the room
	RoomID room = c.createRoom(
		MatrixRoomPresetEnum.private_chat, false, null, null,
		true, [user_id]);

	/// Store the room id in the account data
	JSONValue dat = c.getAccountData("m.direct");
	import std.stdio;

	writeln(dat);
	if ("error" in dat)
		dat = JSONValue();

	if (dat.isNull)
	{
		dat["content"] = JSONValue();
		dat["content"][user_id.toString] = JSONValue();
		dat["content"][user_id.toString] = [room.toString];
	}
	else
	{
		if (!(user_id in dat["content"]))
			dat["content"][user_id] = [room.toString];
		else
			dat["content"][user_id] ~= room.toString;
	}

	c.setAccountData("m.direct", dat);
	return room;
}

RoomID getOrCreateDirectMessageRoom(MatrixClient c, UserID user_id)
{
	string roomId = c.getDirectMessageRoom(user_id);
	return roomId ? RoomID(roomId) : c.createDirectMessageRoom(user_id);
}
